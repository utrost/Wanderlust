import gzip
import json
import sys
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_network import normalize, exclusion, edge_id

BBOX = [8, 52, 9, 54]
XML = b'''<osm><node id="1" lon="8.1" lat="53"/><node id="2" lon="8.2" lat="53"/>
<node id="3" lon="8.3" lat="53"/><node id="4" lon="8.2" lat="53.1"/>
<way id="10"><nd ref="1"/><nd ref="2"/><nd ref="3"/><tag k="highway" v="residential"/></way>
<way id="11"><nd ref="2"/><nd ref="4"/><tag k="highway" v="footway"/></way></osm>'''

class NetworkTests(unittest.TestCase):
    def test_activity_and_roadside_metadata_are_preserved(self):
        raw = XML.replace(b'<tag k="highway" v="footway"/>', b'<tag k="highway" v="footway"/><tag k="bicycle" v="designated"/><tag k="footway" v="sidewalk"/>')
        network, _ = normalize(raw, BBOX)
        path = next(f['properties'] for f in network['features'] if f['properties']['highway']=='footway')
        self.assertEqual(path['bicycle'], 'designated')
        self.assertEqual(path['footway'], 'sidewalk')
    def test_junctions_are_split_and_ids_stable_on_reorder_and_reverse(self):
        original, report = normalize(XML, BBOX)
        self.assertEqual(report['edges'], 3)
        self.assertEqual(report['connected_components'], 1)
        root = ET.fromstring(XML)
        for way in root.findall('way'):
            refs = way.findall('nd')
            for ref in refs: way.remove(ref)
            way.extend(reversed(refs))
        root[:] = list(reversed(list(root)))
        changed, _ = normalize(ET.tostring(root), BBOX)
        self.assertEqual(original['features'], changed['features'])
        self.assertEqual(original['wanderlust_network']['network_version'], changed['wanderlust_network']['network_version'])
        for feature in original['features']:
            self.assertLess(feature['id'], 2**53)
        self.assertEqual(edge_id(10,1,2), edge_id(10,2,1))

    def test_shape_points_are_retained_without_becoming_tiny_edges(self):
        raw = b'<osm><node id="1" lon="8.1" lat="53"/><node id="2" lon="8.10001" lat="53"/><node id="3" lon="8.10002" lat="53.00001"/><way id="10"><nd ref="1"/><nd ref="2"/><nd ref="3"/><tag k="highway" v="footway"/></way></osm>'
        network, _ = normalize(raw,BBOX)
        self.assertEqual(len(network['features']),1)
        self.assertEqual(len(network['features'][0]['geometry']['coordinates']),3)

    def test_committed_bremen_network_rebuilds_exactly(self):
        root = Path(__file__).resolve().parents[2]
        raw = gzip.decompress((root/'data/bremen/source.osm.gz').read_bytes())
        network, _ = normalize(raw,[8.784897,53.062431,8.829756,53.089380])
        expected = json.loads((root/'app/assets/geo/bremen-center.streets.geojson').read_text())
        self.assertEqual(network,expected)

    def test_access_precedence_and_conservative_exclusions(self):
        allowed = [{'highway':'footway'}, {'highway':'cycleway','foot':'yes'},
                   {'highway':'residential','access':'private','foot':'yes'}]
        denied = [{'highway':'footway','foot':'no'}, {'highway':'footway','access':'private'},
                  {'highway':'cycleway'}, {'highway':'motorway','foot':'yes'},
                  {'highway':'pedestrian','area':'yes'}, {'highway':'footway','indoor':'yes'},
                  {'highway':'footway','foot':'yes','foot:conditional':'no @ (night)'}]
        for t in allowed: self.assertIsNone(exclusion(t),t)
        for t in denied: self.assertIsNotNone(exclusion(t),t)

    def test_rejects_incomplete_extract_and_error_response(self):
        for raw in [XML.replace(b'<node id="2" lon="8.2" lat="53"/>', b''), b'<osm><remark>timeout</remark></osm>', b'<html/>']:
            with self.assertRaises(ValueError): normalize(raw, BBOX)

    def test_does_not_clip_into_new_unstable_endpoints(self):
        result, _ = normalize(XML, [8,52,8.25,54])
        self.assertEqual(len(result['features']),2)
        self.assertNotIn(edge_id(10,2,3), [f['id'] for f in result['features']])

    def test_crossing_coordinates_do_not_create_topology(self):
        raw = XML.replace(b'</osm>', b'<node id="5" lon="8.2" lat="53"/><node id="6" lon="8.4" lat="53.1"/><way id="12"><nd ref="5"/><nd ref="6"/><tag k="highway" v="footway"/><tag k="bridge" v="yes"/></way></osm>')
        _, report = normalize(raw,BBOX)
        self.assertEqual(report['connected_components'],2)

    def test_reproducible_bytes_and_version_changes_with_geometry(self):
        a, _ = normalize(XML,BBOX)
        b, _ = normalize(XML,BBOX)
        self.assertEqual(a,b)
        c, _ = normalize(XML.replace(b'8.1"',b'8.11"'),BBOX)
        self.assertEqual([f['id'] for f in a['features']], [f['id'] for f in c['features']])
        self.assertNotEqual(a['wanderlust_network']['network_version'],c['wanderlust_network']['network_version'])

if __name__ == '__main__': unittest.main()
