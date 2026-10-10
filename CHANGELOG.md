# Changelog

Notable project changes are recorded here for users and contributors.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- AMD64 and ARM64 binary downloads and native CI build/test jobs, with a combined
  platform manifest and architecture-specific SBOM attachments.
- Local Buildx tasks for either platform and a multi-platform OCI archive, plus
  checks for tool execution, user identity, extensions, and entrypoint startup.

### Changed

- Align the `UID` environment variable with the actual `jovyan` UID of 1001.
- Use Trivy 0.74.0 for CI scans, matching the pinned image scanner; both platform
  assets are available, while the previous 0.50.2 binary asset URLs returned 404.

### Fixed

- Install Calrissian from commit `a95d87dd213d51b11faea7c6def4ced46d466a4a`
  with compatible isolated dependencies and bundled Dask resources.
- Preinstall Hatch 1.16.2 and its runtime dependencies in an isolated environment,
  avoiding a first-use download; add offline Hatch and Calrissian smoke checks.
- Ensure the default workspace is writable by jovyan for tool configuration.
- Make Mike Farah's pinned `yq` the default command while retaining the Python
  `yq` dependency and `tomlq`/`xq` launchers; smoke-test YAML and TOML processing.

## [1.4.0] - 2026-10-10

### Added

- Pinned CWL and transpiler tooling for EOAP extension runtime requirements.
- CI installation checks for the latest released EOAP Validator, CWL Metadata
  Editor, and CWL UML Viewer VSIXs, with Python dependency checks, validator
  environment setup, and rendering checks for all available UML diagram types.
  Failures block image publication; tested release metadata is saved as an artifact.
- A Taskfile for local AMD64 image builds with image tag and GDAL version overrides.
- Standalone local operation through `JHSINGLE_NATIVE_PROXY_AUTHTYPE=none`,
  with OAuth retained as the default.

### Changed

- Install Node.js 22.15.0 through NVM 0.40.3 instead of distro Node.js packages.
- Require the OpenJDK 17 headless JDK, replacing the optional Java runtime and
  removing the `INSTALL_JRE` build argument.
- Install Calrissian 0.18.1 and its pinned `cwl-utils` 0.40 dependency in an
  isolated virtual environment to avoid conflicts with the image's CWL tooling.
- Document local image builds, standalone usage, and extension compatibility checks.

### Fixed

- Include the C++ compiler and XZ utilities required for the GDAL source build.
- Validate proxy authentication modes and quote entrypoint arguments.

## [1.3.0] - 2026-10-06

### Added

- GDAL 3.12.1 built from source, configurable through the `GDAL_VER` build
  argument, with PROJ dependencies and GDAL environment variables.
- Background Nextcloud synchronization, exposing `/home/jovyan/drive` through
  `/workspace/drive`, with configurable sync intervals, retry backoff, and timeouts.
- Nextcloud SSO and OAuth2 token support, including token refresh through
  JupyterHub and a `NEXTCLOUD_ACCESS_TOKEN` fallback.
- OpenJDK 17 headless runtime, enabled by default and configurable through the
  `INSTALL_JRE` build argument.

### Changed

- Switch the container base image to `quay.io/jupyter/base-notebook:python-3.12`.
- Upgrade code-server from 4.108.1 to 4.138.0 and Trivy from 0.68.2 to 0.74.0.
- Exclude the `eodata` directory from Nextcloud synchronization.

### Fixed

- Set the existing `jovyan` user's UID to 1001 in the Jupyter-based image.
- Validate the workspace and existing `drive` path before creating the Nextcloud
  symlink.
- Quote the `jhsingle-native-proxy>=0.0.9` requirement so the shell does not
  interpret it as output redirection during installation.

## [1.2.0] - 2026-02-02

### Added

- Podman and Skopeo for working with container images.
- Trivy 0.68.2 for vulnerability scanning.

### Changed

- Set the `jovyan` user to UID 1000 and use the existing group with GID 100.

## [1.1.0] - 2026-01-21

First release recorded in this changelog, summarizing the functionality available
at the earliest Git tag.

### Added

- Browser-based code-server development environment with a JupyterHub-compatible
  entrypoint and port 8888 support.
- Kubernetes and workflow tooling, including kubectl, Skaffold, Task, ORAS,
  cwltool, cwltest, and Calrissian.
- AWS CLI with endpoint configuration support, Bash kernel, uv, Hatch, and
  JSON, YAML, and TOML utilities.
- A non-root `jovyan` user with passwordless sudo and `/workspace` as the working
  directory.
- Container publishing to GHCR with branch-based and release-based image tags.

### Changed

- Refactor the image around Python 3.12.11 on Debian Bookworm, pin standalone
  tooling versions, and install code-server 4.108.1 from its release tarball.
- Refactor the CI container build and publishing workflow.

[Unreleased]: https://github.com/EOEPCA/pde-code-server/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/EOEPCA/pde-code-server/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/EOEPCA/pde-code-server/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/EOEPCA/pde-code-server/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/EOEPCA/pde-code-server/releases/tag/v1.1.0
