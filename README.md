# Processor Development Environment (PDE) Container image

The Processor Development Environment provides a rich, interactive environment in which processing algorithms and services are developed, tested, debugged and ultimately packaged so that they can be deployed to the platform and published via the marketplace.

This repository contains a Dockerfile to build a container that exposes [Code Server](https://github.com/cdr/code-server) within a the ApplicationHub.

## Getting Started

### Prerequisites

- [Docker](https://www.docker.com/) installed on your machine.
- [ApplicationHub](https://eoepca.github.io/application-hub-context/) installed and configured.

### Building the Docker Image

To build the Docker image, run the following command:

```bash
docker build -t eoepca/pde-code-server .
```

## Installed Tooling

This image is based on Debian bookworm and Python 3.12, and provides a curated set of development, Kubernetes, and Earth-Observation workflow tools.

All non-distro binaries are pinned to explicit versions to ensure reproducibility.

### Base System

- OS: Debian GNU/Linux 12 (bookworm)
- Python: 3.12.11
- Node.js: 18.x (Debian package)
- npm: bundled with Node.js

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

- code-server: 4.108.1

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
