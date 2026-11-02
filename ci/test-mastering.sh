#!/usr/bin/env bash
# Execute the unmodified workshop init script against disposable storage and S3.
set -euo pipefail
image="${1:?image required}"
platform="${2:?platform required}"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixtures="${3:-$repo_dir/ci/fixtures/mastering-app-package}"
fixtures="$(cd "$fixtures" && pwd)"
name="pde-mastering-$$"
cleanup() {
  docker rm -f "$name-init" "$name-server" "$name-s3" >/dev/null 2>&1 || true
  docker volume rm "$name-workspace" >/dev/null 2>&1 || true
  docker network rm "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker network create "$name" >/dev/null
docker volume create "$name-workspace" >/dev/null
docker run -d --platform "$platform" --name "$name-s3" --network "$name" \
  --network-alias eoap-mastering-app-package-localstack \
  -e SERVICES=s3 localstack/localstack:4.0.3 >/dev/null
ready=false
for ((i=0; i<90; i++)); do
  if docker exec "$name-s3" awslocal s3 ls >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
[[ "$ready" == true ]] || { docker logs "$name-s3"; exit 1; }
# Match a PVC made writable through the chart's fsGroup=100.
docker run --rm --platform "$platform" --user root --entrypoint bash \
  -v "$name-workspace:/workspace" "$image" -ec 'chown 1001:100 /workspace'
docker run --name "$name-init" --platform "$platform" --network "$name" \
  --entrypoint bash -v "$name-workspace:/workspace" \
  -v "$fixtures:/opt/init:ro" "$image" -ec '
    bash /opt/init/init.sh
    test -d /workspace/mastering-app-package/.git
    test "$(readlink /workspace/extensions)" = /workspace/.local/share/code-server/extensions
    code-server --list-extensions > /tmp/extensions
    for extension in ms-python.python redhat.vscode-yaml sbg-rabix.benten-cwl ms-toolsai.jupyter; do
      grep -Fxi "$extension" /tmp/extensions
    done
    /workspace/.venv/bin/python -m pip check
    /workspace/.venv/bin/python -c "import rasterio, click, pystac, loguru, pyproj, shapely, skimage, rio_stac, ipykernel, stactools, calrissian, matplotlib, pandas, nose2"
    /workspace/.venv/bin/kubectl version --client
    jupyter kernelspec list --json | python -c '\''import json,sys; s=json.load(sys.stdin)["kernelspecs"]["mastering_env"]["spec"]; assert s["argv"][0] == "/workspace/.venv/bin/python"'\''
    cp /opt/init/bash-rc /workspace/.bashrc
    bash -ic '\''test "$VIRTUAL_ENV" = /workspace/.venv; python -c "import rasterio"'\''
  '
docker exec "$name-s3" awslocal s3api head-bucket --bucket results
# Match the chart: it invokes code-server directly, bypassing the image entrypoint.
docker run -d --name "$name-server" --platform "$platform" --network "$name" \
  -v "$name-workspace:/workspace" --entrypoint code-server \
  -e XDG_CONFIG_HOME=/workspace/.local -e XDG_DATA_HOME=/workspace/.local/share/ \
  -e XDG_RUNTIME_DIR=/workspace/.local "$image" \
  --auth none --bind-addr 0.0.0.0:8080 --user-data-dir /workspace \
  /workspace/mastering-app-package >/dev/null
for ((i=0; i<90; i++)); do
  if docker exec "$name-server" curl -fsS http://127.0.0.1:8080/ >/dev/null; then
    echo "Mastering init, Python imports, extensions, S3, kernel, shell and chart startup passed ($platform)"
    exit 0
  fi
  sleep 2
done
docker logs "$name-server"
exit 1
