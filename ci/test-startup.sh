#!/usr/bin/env bash
set -euo pipefail
image="${1:?image required}"
platform="${2:?platform required}"
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
    echo "Entrypoint checks passed on $platform"
    exit 0
  fi
  [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]] || exit 1
  sleep 2
done
echo "Entrypoint did not become ready within 180 seconds" >&2
exit 1
