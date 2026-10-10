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
for binary downloads; Node.js, Python packages, GDAL compilation, and apt packages
use the target architecture. All image tool versions remain pinned at their
existing versions, including Nextcloud 3.11.0-1.1build4 and OpenJDK 17.

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

The proxy uses OAuth by default for ApplicationHub deployments. For standalone
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
user identity (UID 1001 / GID 100), Calrissian isolation, Nextcloud symlink, and
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
commands without networking, verifies Calrissian's Git commit provenance, Dask
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

This image is based on the Jupyter Python 3.12 base notebook image (currently
Ubuntu 24.04) and provides a curated set of development, Kubernetes, and
Earth-Observation workflow tools.

All non-distro binaries are pinned to explicit versions to ensure reproducibility.

### Base System

- OS: Ubuntu 24.04 (from the current Jupyter base image)
- Python: 3.12.11
- NVM: v0.40.3, installed at `/opt/nvm`
- Node.js: v22.15.0, installed via NVM and available on `PATH`
- npm: bundled with Node.js 22
- Java: OpenJDK 17 JDK (headless), required and installed from distro packages

Installed system utilities:

- curl, wget
- git
- sudo
- nano
- net-tools
- graphviz
- file
- tree
- CA certificates

### code-server

- code-server: 4.138.0

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

- hatch: 1.16.2

  Python project manager and build tool, installed with all runtime dependencies
  in `/opt/hatch-venv`, using the base image's native Python on AMD64 and ARM64.
  `/usr/local/bin/hatch` links to its console script. Jovyan can use it offline
  without downloading Hatch itself. `HATCH_CONFIG`, `HATCH_DATA_DIR`, and
  `HATCH_CACHE_DIR` point to writable locations under `/home/jovyan`, independent
  of the `/workspace` project mount. Project environment creation, project
  dependencies, plugins, or additional Python versions may still need network
  access; the offline smoke check only reads local project metadata.

### User & Runtime Environment

- User: jovyan
- UID / GID: 1001 / 100
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

Images are built with Buildx. Each platform is tested, scanned with Trivy 0.74.0,
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
