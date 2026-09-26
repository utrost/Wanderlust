#!/usr/bin/env python3
"""Create a small reproducible OSM XML snapshot from regional PBF (pyosmium).

Keeps highway ways touching the bbox, their complete nodes, and tags. Removes
contributor metadata. The normalizer later excludes edges crossing the boundary.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import osmium


class Extract(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.bbox = bbox
        self.node_tags = {}
        self.nodes = {}
        self.ways = {}

    def node(self, node):
        if node.tags:
            self.node_tags[node.id] = dict(node.tags)

    def way(self, way):
        if 'highway' not in way.tags:
            return
        west,south,east,north = self.bbox
        nodes = [(n.ref,n.lon,n.lat) for n in way.nodes]
        if not any(west <= lon <= east and south <= lat <= north for _,lon,lat in nodes):
            return
        self.ways[way.id] = ([n[0] for n in nodes],dict(way.tags))
        for nid,lon,lat in nodes:
            self.nodes[nid] = (lon,lat)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--bbox',default='8.784897,53.062431,8.829756,53.089380')
    args = parser.parse_args()
    handler = Extract(list(map(float,args.bbox.split(','))))
    handler.apply_file(str(args.input),locations=True)
    with osmium.io.Reader(str(args.input)) as reader:
        timestamp = reader.header().get('osmosis_replication_timestamp')
    root = ET.Element('osm',version='0.6',generator='wanderlust-extract-v1')
    ET.SubElement(root,'meta',osm_base=timestamp)
    def add_tags(element, tags):
        for key,value in sorted(tags.items()): ET.SubElement(element,'tag',k=key,v=value)
    for nid,(lon,lat) in sorted(handler.nodes.items()):
        node = ET.SubElement(root,'node',id=str(nid),lon=f'{lon:.7f}',lat=f'{lat:.7f}')
        add_tags(node,handler.node_tags.get(nid,{}))
    for wid,(nodes,tags) in sorted(handler.ways.items()):
        way = ET.SubElement(root,'way',id=str(wid))
        for nid in nodes: ET.SubElement(way,'nd',ref=str(nid))
        add_tags(way,tags)
    raw = ET.tostring(root,encoding='utf-8',xml_declaration=True)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(gzip.compress(raw,mtime=0) if args.output.suffix == '.gz' else raw)
    print(json.dumps({'nodes':len(handler.nodes),'ways':len(handler.ways),
        'osm_base':timestamp,'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),
        'xml_sha256':hashlib.sha256(raw).hexdigest()},indent=2))


if __name__ == '__main__': main()
