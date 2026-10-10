# Processor Development Environment (PDE) Container image

The Processor Development Environment provides a rich, interactive environment in which processing algorithms and services are developed, tested, debugged and ultimately packaged so that they can be deployed to the platform and published via the marketplace.

This repository contains a Dockerfile to build a container that exposes [Code Server](https://github.com/cdr/code-server) within a the ApplicationHub.

## Getting Started

### Prerequisites

- [Docker](https://www.docker.com/) installed on your machine.
- [ApplicationHub](https://eoepca.github.io/application-hub-context/) installed and configured.

### Building the Docker Image

Build the local AMD64 image with:

```bash
docker build --platform=linux/amd64 -t eoepca/pde-code-server:local .
```

With [Task](https://taskfile.dev/) installed, run `task build` (or `task`).
Override the image tag or GDAL version when needed:

```bash
task build IMAGE=eoepca/pde-code-server:dev GDAL_VER=3.12.1
```

The image includes the required OpenJDK 17 JDK and is built for AMD64 because
the standalone binaries used by the image are AMD64 builds.

### Running Locally

The proxy uses OAuth by default for ApplicationHub deployments. For standalone
local use, disable proxy authentication and bind the service to localhost:

```bash
docker run --rm -it \
  --platform=linux/amd64 \
  -e JHSINGLE_NATIVE_PROXY_AUTHTYPE=none \
  -p 127.0.0.1:8888:8888 \
  -v "$PWD:/workspace" \
  eoepca/pde-code-server:local
```

Open <http://127.0.0.1:8888>. If port 8888 is already in use, change the host
port (the first port in `-p`) and use that port in the URL. The container
image must be rebuilt after changes to the entrypoint. At startup, `nc-sync`
creates `/workspace/drive` as a symlink to `/home/jovyan/drive` inside the
container. With the project directory mounted at `/workspace`, this symlink
also appears in the project directory on the host; it is generated runtime
state and should not be committed.

## Installed Tooling

### Extension compatibility checks

Before publishing an image, CI downloads the latest stable release VSIXs from
`eoap/eoap-validator-vscode`, `eoap/cwl-metadata-editor`, and
`eoap/cwl-uml-viewer`. It installs them with `code-server` as the image's default
user and checks the installed IDs and versions. It also checks Python dependency
consistency, installs the validator's bundled wheel in a fresh virtual environment,
loads its CLI, and renders the UML viewer's sample through its installed Python
bridge and bundled Java renderer for every available diagram type.

Failures block image publication. The tested release tags and download URLs are
saved as a CI artifact. These checks use the image's default runtime settings;
they do not exercise editor UI interactions or extension activation. Latest
upstream releases are intentionally used, so a new incompatible release can fail
CI without changes here. Extensions are installed only in the disposable test
container.

To run the same check against a locally built image:

```bash
python3 ci/test-extensions.py download /tmp/pde-extension-vsix
docker run --rm --platform linux/amd64 --entrypoint python3 \
  -v "$PWD/ci:/opt/extension-ci:ro" \
  -v /tmp/pde-extension-vsix:/opt/extension-vsix:ro \
  eoepca/pde-code-server:local \
  /opt/extension-ci/test-extensions.py test /opt/extension-vsix
```

This image is based on Debian bookworm and Python 3.12, and provides a curated set of development, Kubernetes, and Earth-Observation workflow tools.

All non-distro binaries are pinned to explicit versions to ensure reproducibility.

### Base System

- OS: Debian GNU/Linux 12 (bookworm)
- Python: 3.12.11
- NVM: v0.40.3, installed at `/opt/nvm`
- Node.js: v22.15.0, installed via NVM and available on `PATH`
- npm: bundled with Node.js 22
- Java: OpenJDK 17 JDK (headless), required and installed from Debian packages

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

* calrissian: 0.18.1

  CWL runner for Kubernetes.

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

  Python project manager and build tool, installed as a standalone binary.

### User & Runtime Environment

- User: jovyan
- UID / GID: 1001
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

Images are built using Kaniko and pushed using OCI-compliant tooling.

### Tagging Strategy

The image tag is derived automatically from the Git reference that triggered the build:


| Git reference    | Image tag    | Purpose                            |
| ---------------- | ------------ | ---------------------------------- |
| `develop` branch | `latest-dev` | Development and integration builds |
| `main` branch    | `latest`     | Stable branch builds               |
| Git tag `vX.Y.Z` | `X.Y.Z`      | Immutable release builds           |
