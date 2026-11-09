#!/usr/bin/env bash
# Exercise rootless Podman inside a disposable privileged outer container.
# An anonymous workspace volume mirrors a PVC and avoids overlay-on-overlay.
# Docker removes that volume with the container; no host Docker socket is mounted.
set -euo pipefail
image="${1:?image required}"
platform="${2:?platform required}"
docker run --rm -i --privileged --platform "$platform" -v /workspace --entrypoint bash "$image" -se <<'SCRIPT'
set -euo pipefail
test "$(id -u)" = 1000
test -u /usr/bin/newuidmap
test -u /usr/bin/newgidmap
# Require subordinate ranges, not just a single-ID fallback namespace.
podman unshare cat /proc/self/uid_map /proc/self/gid_map | python -c '
import sys
rows = [list(map(int, line.split())) for line in sys.stdin]
assert len(rows) == 4 and rows[1][2] >= 65536 and rows[3][2] >= 65536, rows
'
context="$(mktemp -d)"
trap 'rm -rf "$context"' EXIT
cat > "$context/Containerfile" <<'CONTAINERFILE'
FROM docker.io/library/python:3.12-slim
RUN python -c 'import os; assert os.stat("/etc/gshadow").st_gid == 42; open("/mapped-owner", "w").close(); os.chown("/mapped-owner", 1234, 42)'
USER 1234:42
CMD ["python", "-c", "import os; s=os.stat('/mapped-owner'); assert (os.getuid(),os.getgid(),s.st_uid,s.st_gid)==(1234,42,1234,42); print('Nested build and non-root execution passed')"]
CONTAINERFILE
podman build --tag localhost/pde-podman-test "$context"
podman run --rm localhost/pde-podman-test
SCRIPT
