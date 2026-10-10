#!/usr/bin/env bash
# Run inside the image as its default user, exercising commands through PATH.
set -euo pipefail
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
version="$(yq --version)"
[[ "$version" == 'yq (https://github.com/mikefarah/yq/) version v4.45.1' ]]
printf 'image_version: "1.4.0"\n' > "$fixture_dir/image.yaml"
[[ "$(yq eval '.image_version' "$fixture_dir/image.yaml")" == '1.4.0' ]]
printf '[image]\nversion = "1.4.0"\n' > "$fixture_dir/image.toml"
[[ "$(tomlq -r '.image.version' "$fixture_dir/image.toml")" == '1.4.0' ]]
python -m pip check
printf 'Default yq, TOML processing, and Python dependencies passed: %s\n' "$version"
