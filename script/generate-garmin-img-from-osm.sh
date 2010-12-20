#!/bin/sh

perl /var/www/osm.nix.is/script/generate-garmin-img-from-osm \
    --date=$(date --iso-8601) \
    --osm "/var/www/osm.nix.is/dump/$(date --iso-8601).osm.bz2" \
    --min-osm-size=2000000 \
    --mkgmap-path=/usr/share/mkgmap/mkgmap.jar \
    --mapname 13314530 \
    --description="Iceland OSM" \
    --country-name=ICELAND \
    --country-abbr=ICE \
    --out-dir /var/www/osm.nix.is \
    --out-file=Iceland.osm \
    --osm2mp-dir=/home/avar/src/osm.nix.is/osm2mp \
    --out-mp=Iceland.mp 2>&1 \
    | ack -v '^SEVERE \(RoadNetwork\)'
