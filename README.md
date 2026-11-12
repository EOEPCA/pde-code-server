# Processor Development Environment (PDE) Container image

The Processor Development Environment provides a rich, interactive environment in which processing algorithms and services are developed, tested, debugged and ultimately packaged so that they can be deployed to the platform and published via the marketplace.

This repository contains a Dockerfile to build a container that exposes [Code Server](https://github.com/cdr/code-server) within a the ApplicationHub.

## Getting Started

### Prerequisites

- [Docker](https://www.docker.com/) installed on your machine.
- [ApplicationHub](https://eoepca.github.io/application-hub-context/) installed and configured.

### Building the Docker Image

Build a local image for AMD64 or ARM64 with:

```bash
task build PLATFORM=linux/amd64 IMAGE=eoepca/pde-code-server:amd64
task build PLATFORM=linux/arm64 IMAGE=eoepca/pde-code-server:arm64
```

Install [Task](https://taskfile.dev/) and Docker with Buildx. `task build` (or
`task`) defaults to `linux/amd64` and `eoepca/pde-code-server:local`.
Override the image tag or GDAL version when needed:

```bash
task build IMAGE=eoepca/pde-code-server:dev GDAL_VER=3.12.1
```

Both `linux/amd64` and `linux/arm64` are supported. BuildKit supplies `TARGETARCH`
for binary downloads; Node.js, Python packages, GDAL compilation, and Fedora RPM packages
use the target architecture. code-server is upgraded to 4.144.0. Nextcloud follows Fedora 44 packages;
Java remains OpenJDK 17, supplied by Eclipse Temurin. Other explicitly pinned
tool versions are retained.

Use a native Docker host for the selected platform when possible. Cross-platform
builds and tests require QEMU/binfmt registration (for example,
`docker run --privileged --rm tonistiigi/binfmt --install arm64` on an AMD64 host).
GDAL source compilation under emulation can take substantially longer.

To build both platforms into a local OCI archive without publishing:

```bash
docker buildx create --name pde-multi --driver docker-container --use
docker buildx inspect --bootstrap
task build:multi OUTPUT=/tmp/pde-code-server-multi.oci.tar
```

The OCI archive contains both platforms. For local runtime testing, use the
single-platform `task build` commands above, which load an image into Docker.
Choose distinct tags to keep both images available.

### Running Locally

The proxy uses `/healthz` for code-server readiness with a 120-second cold-start
window. It uses OAuth by default for ApplicationHub deployments. For standalone
local use, disable proxy authentication and bind the service to localhost:

```bash
docker run --rm -it \
  --platform="${PLATFORM:-linux/amd64}" \
  -e JHSINGLE_NATIVE_PROXY_AUTHTYPE=none \
  -p 127.0.0.1:8888:8888 \
  -v "$PWD:/workspace" \
  eoepca/pde-code-server:local
```

Set `PLATFORM=linux/arm64` for an ARM64 local image.

Open <http://127.0.0.1:8888>. If port 8888 is already in use, change the host
port (the first port in `-p`) and use that port in the URL. The container
image must be rebuilt after changes to the entrypoint. At startup, `nc-sync`
creates `/workspace/drive` as a symlink to `/home/jovyan/drive` inside the
container. With the project directory mounted at `/workspace`, this symlink
also appears in the project directory on the host; it is generated runtime
state and should not be committed.

## Building containers with rootless Podman

The image runs Podman as `jovyan` (UID 1000, GID 100). It provides subordinate
UID/GID ranges in `/etc/subuid` and `/etc/subgid`, and root-owned setuid
`newuidmap`/`newgidmap` helpers. The outer container must permit nested user
namespaces and helper privilege escalation. The APEx privileged pod setup can
provide this; the runtime user must match the image account.
Keep the main container and init-container identity aligned with UID 1000.

For an existing Fedora image affected by missing helper privileges, run these
commands in the code-server terminal **as jovyan (UID 1000)**:

```bash
sudo chown root:root /usr/bin/newuidmap /usr/bin/newgidmap
sudo chmod 4755 /usr/bin/newuidmap /usr/bin/newgidmap
podman system migrate
podman unshare cat /proc/self/uid_map /proc/self/gid_map
podman pull docker.io/library/python:3.12-slim
```

`podman system migrate` stops that user's running Podman containers and replaces
the cached user namespace. Each mapping should include the user's own ID plus
at least 65,536 subordinate IDs. If the ranges are absent or the actual UID differs from
1000, correct the deployment identity/ranges first. If helpers still report
`Operation not permitted`, inspect the outer pod's privilege-escalation and
user-namespace restrictions. Do not use `podman system reset` for this repair;
it deletes container storage. The terminal repair lasts only until the outer
container is replaced; rebuild the image for the persistent fix.

Keep Podman storage on the mounted workspace volume. Nested overlay storage in
Docker's writable container layer produced an `exec ... Invalid argument` error
in local testing; an independent workspace volume worked with the default driver.
The regression test uses an anonymous workspace volume and a privileged outer
container, then pulls Python slim, builds a layer with UID 1234/GID 42 ownership,
and runs it as that non-root user. CI runs it on both architectures:

```bash
task test:podman IMAGE=eoepca/pde-code-server:podman-fix-arm64 PLATFORM=linux/arm64
```

This test passed locally on ARM64 on 2026-11-04 using the prior validated image
plus the helper-permissions fix. AMD64 execution remains covered by CI.

## Mastering Application Package compatibility

The image uses `jovyan` (1000:100), `HOME=/workspace`, passwordless sudo,
Python 3.12, Conda, Bash/Python notebook kernels, NVM, all existing PDE tools,
and the ApplicationHub proxy/Nextcloud entrypoint. The workshop Helm chart can
continue running its init container and direct code-server command unchanged.
Workspace volumes must be writable by UID 1000 or GID 100 (`fsGroup: 100`).

Run the integration check with disposable Docker volumes and LocalStack:

```bash
bash ci/test-mastering.sh eoepca/pde-code-server:fedora-arm64 linux/arm64
# Test the current local workshop files instead of the checked-in snapshot:
bash ci/test-mastering.sh eoepca/pde-code-server:fedora-arm64 linux/arm64 \
  /Users/mlongobardo/projects/dev-platform-eoap/mastering-app-package/files
```

This executes the unmodified `init.sh`, verifies all four extensions, geospatial
Python imports, pip dependencies, the kernel interpreter, interactive venv
activation, downloaded kubectl, and S3 bucket creation, then starts code-server
using the chart's command and XDG settings. It needs network access for GitHub,
Open VSX, PyPI, Kubernetes downloads, and the LocalStack image. It does not test
Kubernetes scheduling, a real Nextcloud service, or browser extension activation.
CI runs this check on both architectures before publishing.

The fixture in `ci/fixtures/mastering-app-package` was copied from the local
workshop checkout at commit `49bb077b8753bddfb215827a04a3cf61d265811b`;
refresh it when the workshop initialization changes.

Local validation on 2026-11-02 passed on ARM64: tool and dependency checks,
all three released EOAP extensions (including UML rendering), the current local
workshop `init.sh`, and both direct and proxied startup. AMD64 is covered by the
native CI job but was not built or executed locally during this migration.
The tested local image is `eoepca/pde-code-server:fedora-arm64`.

To rerun only the proxy/Nextcloud-symlink startup check:

```bash
bash ci/test-startup.sh eoepca/pde-code-server:fedora-arm64 linux/arm64
```

## Installed Tooling

### Extension compatibility checks

Before publishing an image, CI builds and tests AMD64 and ARM64 on native
GitHub runners (`ubuntu-24.04` and `ubuntu-24.04-arm`). It downloads the latest stable release VSIXs from
`eoap/eoap-validator-vscode`, `eoap/cwl-metadata-editor`, and
`eoap/cwl-uml-viewer`. It installs them with `code-server` as the image's default
user and checks the installed IDs and versions. It also checks Python dependency
consistency, installs the validator's bundled wheel in a fresh virtual environment,
loads its CLI, and renders the UML viewer's sample through its installed Python
bridge and bundled Java renderer for every available diagram type.

Both architectures use the same downloaded VSIXs. Tool execution, ELF binary architecture, image platform,
user identity (UID 1000 / GID 100), Calrissian isolation, Nextcloud symlink, and
standalone entrypoint startup are checked on each platform.

Failures block image publication. The tested release tags and download URLs are
saved as a CI artifact. These checks use the image's default runtime settings;
they do not exercise editor UI interactions or extension activation. Latest
upstream releases are intentionally used, so a new incompatible release can fail
CI without changes here. Extensions are installed only in the disposable test
container.

To run the full checks against each locally built image:

```bash
task test PLATFORM=linux/amd64 IMAGE=eoepca/pde-code-server:amd64
task test PLATFORM=linux/arm64 IMAGE=eoepca/pde-code-server:arm64
```

`task test` downloads the latest VSIXs, then checks tools, extensions, and startup.
It also verifies that the default `yq` is Mike Farah's pinned v4.45.1, reads a
YAML fixture with `yq eval`, reads a TOML fixture with `tomlq`, and runs
`python -m pip check`. The Python `yq` package remains installed for `tomlq`;
only its conflicting `yq` launcher is replaced, leaving Conda's PATH intact.
The focused runtime check also runs Hatch version and local project metadata
commands, creates and activates a default environment without networking (skipping
project installation), verifies Calrissian's Git commit provenance, Dask
import, CLI flags, and bundled schema/init/dispose scripts, and checks both
isolated environments' dependencies. It does not execute Dask on Kubernetes.
To run these checks against a loaded image on either platform:

```bash
docker run --rm --network none --platform linux/amd64 --entrypoint bash \
  -v "$PWD/ci:/opt/image-ci:ro" eoepca/pde-code-server:amd64 /opt/image-ci/test-runtime.sh
docker run --rm --network none --platform linux/arm64 --entrypoint bash \
  -v "$PWD/ci:/opt/image-ci:ro" eoepca/pde-code-server:arm64 /opt/image-ci/test-runtime.sh
```

To reuse the same downloaded release assets for both platforms:

```bash
python3 ci/test-extensions.py download /tmp/pde-extension-vsix
bash ci/test-image.sh eoepca/pde-code-server:amd64 linux/amd64 /tmp/pde-extension-vsix
bash ci/test-image.sh eoepca/pde-code-server:arm64 linux/arm64 /tmp/pde-extension-vsix
```

The UML viewer's bundled dependencies are tested as shipped, including its native
Python modules; CI does not patch the VSIX or skip rendering on ARM64. A future
upstream incompatibility will fail the corresponding platform check.

This image uses Fedora 44, following the Fedora recipe in coder/code-server
with the PDE runtime contract preserved. The complete Python 3.12 Conda/Jupyter
environment is copied from the Jupyter base notebook image, so notebook tools
and `/opt/conda` paths remain available. Fedora supplies the OS and system tools.

### Dependency update policy

Versions use `major.minor.patch`. All direct dependencies listed in
`requirements*.txt` use **exact `==` pins**, including patch versions. Python
updates require an explicit edit and validation. For selected DNF packages,
major versions are fixed while minor/patch versions and Fedora RPM release
updates remain available. Version limits do not guarantee that updates never
break behavior or contain every security fix.

| Dependencies | Policy |
| --- | --- |
| Python runtime tools | Exact versions in `requirements.txt` and `requirements-cwl-uml.txt`; no automatic direct dependency upgrades. |
| Podman | Exactly **4.9.5**, with build and CI guards requiring **4.9.x**. Update `PODMAN_VERSION` explicitly for another 4.9 patch. |
| Node.js | Latest **22.x** when its build layer runs; `/opt/node` keeps PATH independent of the resolved version. |
| Fedora packages | Fedora **44**, with selected application/helper major versions constrained by `dnf-versionlock.toml`; other RPMs follow Fedora updates. |
| Python/Jupyter and Java base images | Python **3.12** and Java **17** tags; their bundled packages and OS layers may update. |
| Downloaded standalone tools, NVM, GDAL, Hatch | Existing exact versions retained; update their Dockerfile arguments explicitly and run CI. |
| Calrissian | Existing Git commit retained in its isolated environment. |
| CI tooling | GitHub Actions retain major tags; PyYAML stays on **6.0.x**; downloaded scan/publish binaries retain exact releases. |

Fedora 44 [packages Podman 5.x](https://packages.fedoraproject.org/pkgs/podman/podman/index.html),
so the image builds 4.9.5 and its rootless helper from upstream source in a
separate Fedora 44 stage. Runtime libraries and container/network helpers still
receive Fedora updates. DNF excludes Podman packages to prevent replacing this
compatibility exception. This avoids mixing old Fedora repositories into the
image. The exception addresses the requested version rollback; verify the
original cgroup problem in the deployment after rebuilding. Fixes available
only in newer Podman branches are not included, and its vendored Go dependencies
stay at the upstream 4.9.5 versions.

The checked-in [DNF5 versionlock policy](dnf-versionlock.toml) is copied into
both Fedora stages **before installation or upgrade** and stays in the final
image for subsequent DNF transactions. It constrains Git 2, Git LFS 3,
Nextcloud 35, Skopeo 1, Conmon 2, crun 1, Netavark/Aardvark 1,
slirp4netns/fuse-overlayfs 1, Graphviz 14, PROJ 9, GPGME 2, and libseccomp 2.
Related split library/development packages are constrained where applicable.
RPM epochs are included explicitly because they take precedence over version
numbers. See the [DNF5 versionlock documentation](https://dnf5.readthedocs.io/en/latest/commands/versionlock.8.html).

These limits allow fixes within the named major series, including RPM release
updates such as `-1.fc44` to `-2.fc44`. If Fedora removes compatible packages or
new dependencies conflict with these limits, the build should fail rather than
silently cross the ceiling. Review the policy explicitly in that case. Base OS
libraries and build compilers not listed in the policy still follow Fedora 44.

These are bounded updates, not a reproducible lockfile. Transitive Python
dependencies still follow upstream requirements, including in the isolated
Hatch and Calrissian environments and the inherited Jupyter environment.
The workshop fixture remains an upstream snapshot; latest extension releases
remain intentional compatibility probes, installed only in disposable tests.

To pick up allowed updates, rebuild with fresh base images and uncached install
layers (a cached build does not check for newer packages):

```bash
docker buildx build --pull --no-cache --platform linux/amd64 \
  --load -t eoepca/pde-code-server:refresh .
task test IMAGE=eoepca/pde-code-server:refresh PLATFORM=linux/amd64
task test:podman IMAGE=eoepca/pde-code-server:refresh PLATFORM=linux/amd64
task test:mastering IMAGE=eoepca/pde-code-server:refresh PLATFORM=linux/amd64
```

Repeat for ARM64 before publishing. Review exact pins and DNF major-version ceilings
monthly and when a relevant security advisory appears; a fix outside the allowed
series requires an explicit version change and both architecture test jobs.
CI generates an SBOM and scans the image, but the current Trivy scan is
report-only and does not block publication for CVEs.

### Base System

- OS: Fedora 44
- Python: 3.12 (Jupyter/Conda toolchain)
- NVM: v0.40.3, installed at `/opt/nvm`
- Node.js: latest 22.x at build time, installed via NVM and available on `PATH`
- npm: bundled with Node.js 22
- Java: Eclipse Temurin OpenJDK 17 JDK, at `/opt/java/openjdk`

Installed system utilities:

- curl, wget
- git, git-lfs
- htop, openssh-clients, zsh, dumb-init
- sudo
- nano
- net-tools
- graphviz
- file
- tree
- CA certificates

### code-server

- code-server: 4.144.0

Installed from official release tarball and available in PATH:

```
/opt/code-server/bin/code-server
```

Provides a browser-based VS Code environment suitable for JupyterHub and remote development setups.

### Kubernetes & OCI Tooling

- kubectl: v1.29.3

  Kubernetes CLI, pinned to a stable upstream release.

- skaffold: 2.17.1

  Continuous development and deployment tool for Kubernetes.

- Task (go-task): v3.41.0

  Task runner used for declarative build and workflow automation.

- oras: 1.3.0

  OCI Registry As Storage client, used for pushing and pulling non-container artifacts (e.g. SBOMs).

- YAML / JSON Utilities

  - yq: v4.45.1

    YAML processor (Go implementation by Mike Farah).

  - jq: jq-1.8.1

    JSON processor.

  Both tools are installed as standalone static binaries.

### Python Tooling

Installed via pip (Python 3.12):

* awscli

  AWS command-line interface.

* awscli-plugin-endpoint

  Endpoint resolution plugin for AWS CLI.

* cwltool

  Reference implementation of the Common Workflow Language.

* calrissian: commit `a95d87dd213d51b11faea7c6def4ced46d466a4a`

  CWL runner for Kubernetes with Dask support, installed from the pinned upstream
  Git commit in `/opt/calrissian-venv`. Its dependencies are resolved together,
  including `cwltool>=3.1.20260108082145`, separately from the image's CWL tooling.
  `CALRISSIAN_COMMIT` is the build argument; changing it also requires updating
  the expected commit in `ci/test-runtime.sh`.

* jhsingle-native-proxy (>= 0.0.9)

  JupyterHub native service proxy.

* bash_kernel

  Bash kernel for Jupyter notebooks (installed system-wide).

* tomlq

  jq-like querying tool for TOML files.

* uv

  Fast Python package installer and resolver.

### Python Build & Packaging

- hatch: 1.16.5

  Python project manager and build tool, installed with all runtime dependencies
  in `/opt/hatch-venv`, using the base image's native Python on AMD64 and ARM64.
  `/usr/local/bin/hatch` links to its console script. Jovyan can use it offline
  without downloading Hatch itself. `HATCH_CONFIG`, `HATCH_DATA_DIR`, and
  `HATCH_CACHE_DIR` point to writable locations under `/home/jovyan`, independent
  of the `/workspace` project mount. Project environment creation, project
  dependencies, plugins, or additional Python versions may still need network
  access; the offline smoke check only reads local project metadata.

### GDAL build cleanup

GDAL is compiled from source, then CMake, GCC/G++, Ninja, PROJ development
headers, and their unused dependencies are removed in the same image layer.
The ARM64 cleanup test removed 53 RPMs (about 348 MiB of installed files).
Compressed image savings vary. PROJ tools and coordinate grids, `xz`, GDAL's
linked runtime libraries, and GDAL's own headers/`gdal-config` remain installed.
CI checks compressed GeoTIFF creation and EPSG reprojection after cleanup.

Compilers are no longer preinstalled for source builds inside the development
environment. If a project needs them, install the required development packages
with `sudo dnf install gcc-c++ cmake ninja-build proj-devel`.

### User & Runtime Environment

- User: jovyan
- UID / GID: 1000 / 100
- Home / Workdir: /workspace
- Passwordless sudo enabled for the user.

### Exposed Port

- 8888 — typically used by JupyterHub / code-server setups.

## Container Image Strategy & Availability

This project publishes container images to GitHub Container Registry (GHCR) following a clear and deterministic tagging strategy aligned with the Git branching and release model.

### Image Registry

Images are published to:

```
ghcr.io/<repository-owner>/pde-code-server
```

The registry owner corresponds to the GitHub repository owner (user or organization).

Images are built with Buildx. Each platform is tested, scanned with Trivy 0.76.1,
and given its own SPDX JSON SBOM. After both platform jobs succeed, CI publishes
the tested images and attaches each SBOM with ORAS to that architecture image's
exact registry digest. It then publishes a combined multi-platform manifest under
the branch or release tag. The SBOMs describe individual platform images, not the
combined index. Vulnerability findings remain informational, as in the previous
workflow. Pull requests run builds and checks without publishing.

### Tagging Strategy

The image tag is derived automatically from the Git reference that triggered the build:


| Git reference    | Image tag    | Purpose                            |
| ---------------- | ------------ | ---------------------------------- |
| `develop` branch | `latest-dev` | Development and integration builds |
| `main` branch    | `latest`     | Stable branch builds               |
| Git tag `vX.Y.Z` | `X.Y.Z`      | Immutable release builds           |
