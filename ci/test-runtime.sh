#!/usr/bin/env bash
# Run as jovyan in a disposable container with --network none.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
test "$(id -u)" = 1001
test -w "$HATCH_CONFIG"
test -w "$HATCH_DATA_DIR"
test -w "$HATCH_CACHE_DIR"
test "$(readlink -f "$(command -v hatch)")" = /opt/hatch-venv/bin/hatch
test "$(readlink -f "$(command -v calrissian)")" = /opt/calrissian-venv/bin/calrissian
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

[[ "$(hatch --version)" == 'Hatch, version 1.16.2' ]]
cat > "$fixture_dir/pyproject.toml" <<'TOML'
[project]
name = "offline-smoke"
version = "1.2.3"
TOML
cd "$fixture_dir"
[[ "$(hatch version)" == '1.2.3' ]]
/opt/hatch-venv/bin/python -m pip check

/opt/calrissian-venv/bin/python - <<'PYTHON'
import json
from importlib import metadata
from pathlib import Path

import calrissian.dask
from packaging.version import Version

expected = "a95d87dd213d51b11faea7c6def4ced46d466a4a"
distribution = metadata.distribution("calrissian")
provenance = json.loads(distribution.read_text("direct_url.json"))
assert provenance["url"].removesuffix(".git").lower() == "https://github.com/duke-gcb/calrissian"
assert provenance["vcs_info"]["vcs"] == "git"
assert provenance["vcs_info"]["commit_id"] == expected, provenance
assert Version(metadata.version("cwltool")) >= Version("3.1.20260108082145")
package = Path(calrissian.dask.__file__).parent
for resource in ("dask/custom_schema/schema.yaml", "dask/init-dask.py", "dask/dispose-dask.py"):
    path = package / resource
    assert path.is_file() and path.stat().st_size > 0, path
    print(f"Verified installed resource: {path}")
print(f"Verified Calrissian commit {expected}, Dask import, and cwltool {metadata.version('cwltool')}")
PYTHON
/opt/calrissian-venv/bin/python -m pip check
calrissian --help > "$fixture_dir/calrissian-help.txt"
for flag in --dask-gateway-url --dask-script-configmap; do
  grep -Fq -- "$flag" "$fixture_dir/calrissian-help.txt"
done
bash "$script_dir/test-yq.sh"
echo 'Offline Hatch, Calrissian package, and YAML/TOML checks passed (no Kubernetes Dask execution tested).'
