#!/usr/bin/env python3
"""Deterministically normalize OSM XML into Wanderlust's street contract v1.

No network calls or third-party Python packages. Input may be .osm or .osm.gz.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

POLICY = 'pedestrian-conservative-v2'
SAFE_INTEGER = (1 << 53) - 1
DEFAULT_HIGHWAYS = {
    'residential', 'living_street', 'footway', 'path', 'pedestrian', 'steps',
    'service', 'unclassified', 'tertiary', 'secondary', 'primary',
    'tertiary_link', 'secondary_link', 'primary_link', 'track',
}
FOOT_ALLOWED = {'yes', 'designated', 'permissive'}
ACCESS_ALLOWED = {'yes', 'permissive'}


def tags(element):
    return {t.attrib['k']: t.attrib['v'] for t in element.findall('tag')}


def exclusion(t):
    highway = t.get('highway', '')
    if highway not in DEFAULT_HIGHWAYS | {'cycleway', 'bridleway'}:
        return 'highway'
    if t.get('area') == 'yes':
        return 'area'
    if t.get('indoor') == 'yes' or 'level' in t:
        return 'indoor'
    if 'foot:conditional' in t or 'access:conditional' in t:
        return 'conditional'
    foot = t.get('foot')
    if foot is not None:
        return None if foot in FOOT_ALLOWED else 'foot'
    if highway in {'cycleway', 'bridleway'}:
        return 'foot_unspecified'
    if t.get('access', 'yes') not in ACCESS_ALLOWED:
        return 'access'
    return None


def blocked_node(t):
    if t.get('foot') in FOOT_ALLOWED:
        return False
    if 'foot' in t and t['foot'] not in FOOT_ALLOWED:
        return True
    return (t.get('access', 'yes') not in ACCESS_ALLOWED
            or 'foot:conditional' in t or 'access:conditional' in t
            or t.get('barrier') in {'wall', 'fence', 'hedge', 'block'})


def edge_id(way, a, b, via=()):
    """52-bit identity of an OSM way/node chain, independent of direction/order.

Moving a node preserves identity; changing its topology creates a new edge.
Full chains distinguish opposite arcs of a loop sharing the same endpoints.
"""
    chain = (a, *via, b)
    chain = min(chain, tuple(reversed(chain)))
    key = f'osm-edge-v2:{way}:' + ','.join(map(str, chain))
    return int(hashlib.sha256(key.encode()).hexdigest()[:13], 16)


def metres(a, b):
    lon1, lat1, lon2, lat2 = map(math.radians, (*a, *b))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(h)))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def normalize(raw, bbox, area_id='bremen-center', name='Bremen center'):
    if len(bbox) != 4 or not all(math.isfinite(n) for n in bbox):
        raise ValueError('bbox must contain four finite coordinates')
    west, south, east, north = bbox
    if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
        raise ValueError('invalid bbox bounds')
    root = ET.fromstring(raw)
    if root.tag != 'osm' or root.find('remark') is not None:
        raise ValueError('expected complete OSM XML without an Overpass error remark')
    nodes = {}
    blocked = set()
    for node in root.findall('node'):
        nid = int(node.attrib['id'])
        pos = [float(node.attrib['lon']), float(node.attrib['lat'])]
        if not (0 < nid <= SAFE_INTEGER and all(map(math.isfinite, pos))
                and abs(pos[0]) <= 180 and abs(pos[1]) <= 90):
            raise ValueError('invalid OSM node')
        if nid in nodes:
            raise ValueError(f'duplicate node {nid}')
        nodes[nid] = pos
        if blocked_node(tags(node)):
            blocked.add(nid)
    def inside(p):
        return west <= p[0] <= east and south <= p[1] <= north
    skipped = Counter()
    features = {}
    seen_ways = set()
    candidates = []
    references = Counter()
    for way in root.findall('way'):
        wid = int(way.attrib['id'])
        if not 0 < wid <= SAFE_INTEGER or wid in seen_ways:
            raise ValueError(f'invalid/duplicate way {wid}')
        seen_ways.add(wid)
        t = tags(way)
        reason = exclusion(t)
        if reason:
            skipped[reason] += 1
            continue
        refs = [int(n.attrib['ref']) for n in way.findall('nd')]
        if len(refs) < 2 or any(n not in nodes for n in refs):
            raise ValueError(f'walkable way {wid} has incomplete nodes')
        # Canonical direction makes length-limited segmentation reproducible.
        refs = min(refs, list(reversed(refs)))
        candidates.append((wid, t, refs))
        references.update(refs)
    for wid, t, refs in candidates:
        pieces = []
        piece = [refs[0]]
        length = 0.0
        for index, node in enumerate(refs[1:], 1):
            length += metres(nodes[piece[-1]], nodes[node])
            piece.append(node)
            if (references[node] > 1 or node in blocked or length >= 60
                    or index == len(refs)-1
                    or inside(nodes[refs[index-1]]) != inside(nodes[node])):
                pieces.append(piece)
                piece = [node]
                length = 0.0
        for chain in pieces:
            chain = min(chain, list(reversed(chain)))
            a, b = chain[0], chain[-1]
            if any(n in blocked for n in chain):
                skipped['blocked_node_edges'] += 1
                continue
            if not all(inside(nodes[n]) for n in chain):
                skipped['boundary_edges'] += 1
                continue
            length = sum(metres(nodes[x],nodes[y]) for x,y in zip(chain,chain[1:]))
            if length < 0.01:
                skipped['degenerate_edges'] += 1
                continue
            eid = edge_id(wid, a, b, chain[1:-1])
            properties = {'osm_way_id': wid, 'from_node': a, 'to_node': b,
                          'highway': t['highway'], 'length_m': round(length, 3)}
            for key in ('name', 'bridge', 'tunnel', 'layer', 'foot', 'bicycle', 'footway', 'access'):
                if key in t:
                    properties[key] = t[key]
            feature = {'type': 'Feature', 'id': eid, 'properties': properties,
                       'geometry': {'type': 'LineString', 'coordinates': [nodes[n] for n in chain]}}
            if eid in features and features[eid] != feature:
                raise ValueError(f'stable edge id collision: {eid}')
            features[eid] = feature
    if not features:
        raise ValueError('no walkable edges in the area')
    ordered = [features[k] for k in sorted(features)]
    version_payload = {'area_id': area_id, 'bbox': bbox, 'policy': POLICY, 'features': ordered}
    version = hashlib.sha256(canonical(version_payload).encode()).hexdigest()
    metadata = {
        'version': 1, 'area_id': area_id, 'name': name, 'network_version': version,
        'policy': POLICY, 'edge_id_scheme': 'sha256-osm-way-node-chain-52bit-v2',
        'source_sha256': hashlib.sha256(raw).hexdigest(),
        'attribution': '© OpenStreetMap contributors',
        'license': 'ODbL-1.0', 'license_url': 'https://www.openstreetmap.org/copyright',
    }
    osm_meta = root.find('meta')
    if osm_meta is not None:
        metadata['osm_base'] = osm_meta.attrib.get('osm_base', '')
    network = {'type': 'FeatureCollection', 'bbox': bbox, 'wanderlust_network': metadata, 'features': ordered}
    return network, evaluate(network, skipped)


def evaluate(network, skipped=None):
    adjacency = defaultdict(set)
    lengths = []
    for f in network['features']:
        p = f['properties']
        a, b = p['from_node'], p['to_node']
        adjacency[a].add(b); adjacency[b].add(a)
        lengths.append(p['length_m'])
    remaining = set(adjacency)
    components = []
    while remaining:
        stack = [remaining.pop()]
        count = 0
        while stack:
            current = stack.pop(); count += 1
            for neighbor in adjacency[current]:
                if neighbor in remaining:
                    remaining.remove(neighbor); stack.append(neighbor)
        components.append(count)
    lengths.sort()
    return {'edges': len(lengths), 'nodes': len(adjacency),
            'connected_components': len(components),
            'largest_component_nodes': max(components),
            'largest_component_node_fraction': round(max(components)/len(adjacency), 4),
            'total_length_km': round(sum(lengths)/1000, 3),
            'median_edge_m': lengths[len(lengths)//2], 'max_edge_m': max(lengths),
            'edges_under_6m': sum(n < 6 for n in lengths),
            'excluded': dict(sorted((skipped or {}).items())),
            'network_version': network['wanderlust_network']['network_version']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--bbox', default='8.784897,53.062431,8.829756,53.089380')
    parser.add_argument('--area-id', default='bremen-center')
    parser.add_argument('--name', default='Bremen center')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    raw = args.input.read_bytes()
    if args.input.suffix == '.gz': raw = gzip.decompress(raw)
    network, report = normalize(raw, list(map(float, args.bbox.split(','))), args.area_id, args.name)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(canonical(network)+'\n')
    if args.report:
        args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
