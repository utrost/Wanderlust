#!/usr/bin/env python3
"""Evaluate real OSM topology with explicitly synthetic (not recorded) walks.

Exercises the actual C ABI. Expected edges come from a route on OSM node ids,
not from the matcher's answers. Reports false positives, missed edges, and time.
"""
import argparse
from collections import defaultdict
import ctypes
from datetime import datetime,timedelta,timezone
import heapq
import json
import math
from pathlib import Path
import time
from build_network import metres


class NativeMatcher:
    def __init__(self, library, network, fill_small_gaps=False):
        self.fill_small_gaps = fill_small_gaps
        self.lib = ctypes.CDLL(str(Path(library).resolve()))
        self.lib.wanderlust_matcher_from_geojson.argtypes = [ctypes.c_char_p]
        self.lib.wanderlust_matcher_from_geojson.restype = ctypes.c_void_p
        self.lib.wanderlust_match_gpx.argtypes = [ctypes.c_void_p,ctypes.c_char_p]
        self.lib.wanderlust_match_gpx.restype = ctypes.c_void_p
        self.lib.wanderlust_match_gpx_options.argtypes = [ctypes.c_void_p,ctypes.c_char_p,ctypes.c_uint8]
        self.lib.wanderlust_match_gpx_options.restype = ctypes.c_void_p
        self.lib.wanderlust_string_free.argtypes = [ctypes.c_void_p]
        self.lib.wanderlust_matcher_free.argtypes = [ctypes.c_void_p]
        self.handle = self.lib.wanderlust_matcher_from_geojson(network.encode())
        if not self.handle: raise ValueError('native loader rejected network')
    def match(self,gpx):
        ptr = self.lib.wanderlust_match_gpx_options(self.handle,gpx.encode(),int(self.fill_small_gaps))
        if not ptr: raise ValueError('native match failed')
        try:
            result = json.loads(ctypes.string_at(ptr))
            if 'error' in result: raise ValueError(result['error'])
            return result
        finally: self.lib.wanderlust_string_free(ptr)
    def close(self): self.lib.wanderlust_matcher_free(self.handle)


def route(network, start, end):
    nodes = {}
    adjacency = defaultdict(list)
    for f in network['features']:
        p = f['properties']; a,b = p['from_node'],p['to_node']
        coords = f['geometry']['coordinates']
        nodes[a],nodes[b] = coords[0],coords[-1]
        for x,y in [(a,b),(b,a)]: adjacency[x].append((y,p['length_m'],f['id']))
    origin = min(nodes,key=lambda n:metres(nodes[n],start))
    target = min(nodes,key=lambda n:metres(nodes[n],end))
    heap = [(0,origin)]; dist = {origin:0}; previous = {}
    while heap:
        cost,node = heapq.heappop(heap)
        if cost != dist[node]: continue
        if node == target: break
        for other,length,edge in sorted(adjacency[node]):
            candidate = cost+length
            if candidate < dist.get(other,math.inf):
                dist[other] = candidate; previous[other] = (node,edge)
                heapq.heappush(heap,(candidate,other))
    if target not in previous: raise ValueError('evaluation route disconnected')
    result = []
    while target != origin:
        source,edge = previous[target]
        result.append((edge,nodes[source],nodes[target]))
        target = source
    features = {f['id']: f['geometry']['coordinates'] for f in network['features']}
    expanded = []
    for edge,a,b in reversed(result):
        coords = features[edge]
        if coords[0] != a: coords = list(reversed(coords))
        expanded.extend((edge,x,y) for x,y in zip(coords,coords[1:]))
    return expanded


def synthetic_gpx(path, noise_m=0, step_m=3):
    points = []; elapsed = 0.0
    for edge,a,b in path:
        distance = metres(a,b)
        steps = max(1,math.ceil(distance/step_m))
        for i in range(steps):
            t = i/steps
            longitude,latitude = a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t
            # Deterministic independent-axis wobble; never presented as field GPS.
            n = len(points)
            latitude += noise_m * math.sin(n*1.73)/111320
            longitude += noise_m * math.cos(n*2.11)/(111320*math.cos(math.radians(latitude)))
            points.append((longitude,latitude,elapsed))
            elapsed += distance/steps/1.3
    points.append((*path[-1][2],elapsed))
    origin = datetime(2026,9,26,9,tzinfo=timezone.utc)
    xml = ['<gpx version="1.1" creator="wanderlust-synthetic-evaluation"><trk><name>SYNTHETIC test trace</name><trkseg>']
    for lon,lat,t in points:
        stamp = (origin+timedelta(seconds=t)).isoformat(timespec='milliseconds').replace('+00:00','Z')
        xml.append(f'<trkpt lon="{lon:.9f}" lat="{lat:.9f}"><time>{stamp}</time></trkpt>')
    xml.append('</trkseg></trk></gpx>')
    return '\n'.join(xml),len(points)


def evaluate(network_text, library, output_dir, step_m=3, fill_small_gaps=False):
    network = json.loads(network_text)
    matcher = NativeMatcher(library,network_text,fill_small_gaps)
    lengths = {f['id']:f['properties']['length_m'] for f in network['features']}
    routes = [
        ('market-to-wall',[8.8073262,53.0759058],[8.810,53.0805]),
        ('schlachte',[8.7985,53.0775],[8.8050,53.0737]),
        ('ostertor',[8.8105,53.0742],[8.8210,53.0725]),
    ]
    rows = []
    output_dir.mkdir(parents=True,exist_ok=True)
    try:
        for name,start,end in routes:
            path = route(network,start,end)
            expected = {p[0] for p in path}
            for noise in (0,2,6):
                gpx,points = synthetic_gpx(path,noise,step_m)
                began = time.perf_counter(); result = matcher.match(gpx); duration = time.perf_counter()-began
                actual = set(result['walked']); correct = actual & expected
                rows.append({'route':name,'synthetic_noise_m':noise,'points':points,
                    'expected_edges':len(expected),'matched_edges':len(actual),
                    'false_positive_edges':len(actual-expected),'missed_edges':len(expected-actual),
                    'precision':round(len(correct)/len(actual),4) if actual else None,
                    'recall':round(len(correct)/len(expected),4),
                    'length_recall':round(sum(lengths[e] for e in correct)/sum(lengths[e] for e in expected),4),
                    'false_positive_length_m':round(sum(lengths[e] for e in actual-expected),1),
                    'match_ms':round(duration*1000,1),
                    'gaps_filled':result['gaps_filled'],'gaps_rejected':result['gaps_rejected']})
                if noise == 0:
                    (output_dir/f'{name}.synthetic.gpx').write_text(gpx)
                    (output_dir/f'{name}.expected.json').write_text(json.dumps(sorted(expected))+'\n')
        report = {'fill_small_gaps':fill_small_gaps, 'network_version':network['wanderlust_network']['network_version'],
                  'method':f'Synthetic traces on independently routed OSM edges, {step_m}m sampling, 1.3m/s. Not real GPS validation.',
                  'results':rows}
        (output_dir/'matching-report.json').write_text(json.dumps(report,indent=2)+'\n')
        return report
    finally: matcher.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--network',type=Path,default=Path('app/assets/geo/bremen-center.streets.geojson'))
    p.add_argument('--library',type=Path,default=Path('target/release/libwanderlust_geo.so'))
    p.add_argument('--output',type=Path,default=Path('tools/out/evaluation'))
    p.add_argument('--step-m',type=float,default=3)
    p.add_argument('--fill-small-gaps',action='store_true')
    p.add_argument('--check',action='store_true',help='Fail on false positives or clean length recall below 80 percent')
    args = p.parse_args()
    if args.step_m <= 0: p.error('--step-m must be positive')
    report = evaluate(args.network.read_text(),args.library,args.output,args.step_m,args.fill_small_gaps)
    print(json.dumps(report,indent=2))
    if args.check and any(row['false_positive_edges'] or (row['synthetic_noise_m'] == 0 and row['length_recall'] < .8) for row in report['results']):
        raise SystemExit('Matching regression: inspect report')

if __name__ == '__main__': main()
