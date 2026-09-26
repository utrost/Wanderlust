#!/usr/bin/env bash
# Build one area's offline basemap (PMTiles) + walkable street network (GeoJSON)
# from an OSM extract. See tools/README.md.
#
#   ./build_tiles.sh <region.osm.pbf> <minLng,minLat,maxLng,maxLat> <area-name>
#
# Outputs: out/<area>.pmtiles, out/<area>.streets.geojson
#
# Status: scaffold. Planetiler and osmium invocations are the intended shape;
# the tile profile still needs tuning against on-device render tests (Phase 0).
set -euo pipefail

PBF="${1:?path to a regional .osm.pbf}"
BBOX="${2:?bbox as minLng,minLat,maxLng,maxLat}"
AREA="${3:?area name, e.g. kreuzberg}"

OUT="$(dirname "$0")/out"
mkdir -p "$OUT"

IFS=',' read -r MINLNG MINLAT MAXLNG MAXLAT <<<"$BBOX"

echo "==> Clipping ${PBF} to ${AREA} bbox"
osmium extract --strategy=complete_ways --bbox "${MINLNG},${MINLAT},${MAXLNG},${MAXLAT}" \
  --overwrite -o "${OUT}/${AREA}.osm.pbf" "${PBF}"

echo "==> Extracting walkable street network → GeoJSON"
# Keep OSM node identity; GeoJSON export of whole ways loses real junctions.
osmium tags-filter "${OUT}/${AREA}.osm.pbf" w/highway \
  --overwrite -o "${OUT}/${AREA}.streets.osm.pbf"
osmium cat "${OUT}/${AREA}.streets.osm.pbf" \
  --overwrite -o "${OUT}/${AREA}.streets.osm"
python3 "$(dirname "$0")/build_network.py" \
  "${OUT}/${AREA}.streets.osm" "${OUT}/${AREA}.streets.geojson" \
  --bbox "$BBOX" --area-id "$AREA" --name "$AREA" \
  --report "${OUT}/${AREA}.network-report.json"

echo "==> Building offline vector tiles (PMTiles) with Planetiler"
# Requires planetiler.jar on PATH or PLANETILER_JAR set.
: "${PLANETILER_JAR:=planetiler.jar}"
java -jar "${PLANETILER_JAR}" \
  --osm-path="${OUT}/${AREA}.osm.pbf" \
  --output="${OUT}/${AREA}.pmtiles" \
  --force

echo "==> Done:"
echo "    ${OUT}/${AREA}.pmtiles"
echo "    ${OUT}/${AREA}.streets.geojson"
