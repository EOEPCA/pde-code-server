#!/usr/bin/env bash
# Run against a loaded image; uses native execution or registered binfmt/QEMU.
set -euo pipefail
image="${1:?image required}"
platform="${2:?platform required}"
vsix_dir="${3:?VSIX directory required}"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
arch="${platform#linux/}"
case "$platform" in linux/amd64|linux/arm64) ;; *) exit 1 ;; esac
actual="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
[[ "$actual" == "$platform" ]] || { echo "Expected $platform, got $actual" >&2; exit 1; }
# Exercise cold-start runtime availability before any network-enabled tool check.
docker run --rm --network none --platform "$platform" --entrypoint bash \
  -v "$repo_dir/ci:/opt/image-ci:ro" "$image" /opt/image-ci/test-runtime.sh
docker run --rm --platform "$platform" --entrypoint bash "$image" -ec '
  test "$(id -u)" = 1001
  test "$UID" = 1001
  test "$(id -un)" = jovyan
  test "$(id -g)" = 100
  test "$(dpkg --print-architecture)" = "$1"
  code-server --version
  node --version
  kubectl version --client=true
  task --version
  skaffold version
  /usr/local/bin/oras version
  yq --version
  jq --version
  hatch --version
  trivy --version
  java -version
  dot -V
  gdalinfo --version
  calrissian --version
  cwltool --version
  cwltest --help >/dev/null
  podman --version
  skopeo --version
  uv --version
  QT_QPA_PLATFORM=offscreen nextcloudcmd --version
  python3 -m pip check
  /opt/calrissian-venv/bin/python -m pip check
  python3 -c "import cwl_loader, cwl2puml"
' bash "$arch"
# Check the ENV value directly: Bash replaces UID with the current numeric UID.
docker run --rm -i --platform "$platform" --entrypoint python3 "$image" - "$arch" <<'PYTHON'
import os
from pathlib import Path
import shutil
import struct
import sys

assert os.environ["UID"] == "1001"
assert os.getuid() == 1001
machine = {"amd64": 62, "arm64": 183}[sys.argv[1]]
executables = ["/opt/code-server/lib/node", shutil.which("node"), shutil.which("trivy"),
               "/opt/hatch-venv/bin/python", "/opt/calrissian-venv/bin/python"]
executables += [f"/usr/local/bin/{name}" for name in
                ("kubectl", "task", "skaffold", "oras", "yq", "jq")]
for executable in executables:
    with Path(executable).open("rb") as stream:
        header = stream.read(20)
    assert header[:4] == b"\x7fELF" and header[5] == 1, executable
    assert struct.unpack("<H", header[18:20])[0] == machine, executable
    print(f"Verified {sys.argv[1]} ELF: {executable}")
PYTHON
docker run --rm --platform "$platform" --entrypoint python3 \
  -v "$repo_dir/ci:/opt/extension-ci:ro" -v "$vsix_dir:/opt/extension-vsix:ro" \
  "$image" /opt/extension-ci/test-extensions.py test /opt/extension-vsix

container=""
# Invoked by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  if [[ -n "$container" ]]; then
    docker logs "$container" || true
    docker rm -f "$container" >/dev/null
  fi
}
trap cleanup EXIT
container="$(docker run -d --platform "$platform" \
  -e JHSINGLE_NATIVE_PROXY_AUTHTYPE=none "$image")"
deadline=$((SECONDS + 180))
while ((SECONDS < deadline)); do
  if docker exec "$container" curl -fsS --max-time 5 http://127.0.0.1:8888/ >/dev/null; then
    docker exec "$container" test -L /workspace/drive
    docker exec "$container" test "$(docker exec "$container" readlink /workspace/drive)" = /home/jovyan/drive
    echo "Image, extensions, and entrypoint checks passed on $platform"
    exit 0
  fi
  [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]] || exit 1
  sleep 2
done
echo "Entrypoint did not become ready within 180 seconds" >&2
exit 1
