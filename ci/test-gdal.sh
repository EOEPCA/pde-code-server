#!/usr/bin/env bash
# Exercise GDAL's shared libraries, raster codecs, and PROJ data after cleanup.
set -euo pipefail
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
gdal-config --version
gdal_create -q -of GTiff -outsize 8 8 -bands 1 -burn 7 \
  -co COMPRESS=DEFLATE -a_srs EPSG:4326 -a_ullr 10 45 11 44 \
  "$fixture_dir/source.tif"
gdalwarp -q -t_srs EPSG:3857 -co COMPRESS=LZW \
  "$fixture_dir/source.tif" "$fixture_dir/projected.tif"
gdalinfo -json -stats "$fixture_dir/projected.tif" | python -c '
import json, sys
info = json.load(sys.stdin)
assert info["driverShortName"] == "GTiff", info
assert "3857" in info["coordinateSystem"]["wkt"], info
band = info["bands"][0]
assert band["minimum"] == 7 and band["maximum"] == 7, band
print("GDAL compressed GeoTIFF and EPSG reprojection checks passed")
'
