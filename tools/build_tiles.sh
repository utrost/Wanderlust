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
osmium extract --bbox "${MINLNG},${MINLAT},${MAXLNG},${MAXLAT}" \
  --overwrite -o "${OUT}/${AREA}.osm.pbf" "${PBF}"

echo "==> Extracting walkable street network → GeoJSON"
# Highways a pedestrian can walk; tags kept minimal for the geo-core loader.
osmium tags-filter "${OUT}/${AREA}.osm.pbf" \
  w/highway=residential,living_street,footway,path,pedestrian,tertiary,secondary,unclassified,service,cycleway,steps,track \
  --overwrite -o "${OUT}/${AREA}.streets.osm.pbf"
osmium export "${OUT}/${AREA}.streets.osm.pbf" \
  --geometry-types=linestring \
  --overwrite -o "${OUT}/${AREA}.streets.geojson"

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
