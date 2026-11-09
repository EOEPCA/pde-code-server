# Retain the complete Python/Jupyter/Conda toolchain while moving the OS to Fedora.
FROM quay.io/jupyter/base-notebook:python-3.12 AS python-runtime
FROM eclipse-temurin:17-jdk AS java-runtime
FROM fedora:44

COPY --from=java-runtime /opt/java/openjdk /opt/java/openjdk
COPY --from=python-runtime /opt/conda /opt/conda
COPY --from=python-runtime /usr/local/bin/start*.py /usr/local/bin/
COPY --from=python-runtime /usr/local/bin/start*.sh /usr/local/bin/
COPY --from=python-runtime /usr/local/bin/fix-permissions /usr/local/bin/
ENV JAVA_HOME=/opt/java/openjdk \
    CONDA_DIR=/opt/conda \
    NB_USER=jovyan \
    NB_UID=1000 \
    NB_GID=100 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    SHELL=/bin/bash \
    PATH=/opt/java/openjdk/bin:/opt/conda/bin:${PATH}

# BuildKit supplies amd64 or arm64 for each target platform.
ARG TARGETARCH
RUN case "${TARGETARCH}" in amd64|arm64) ;; *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; esac

ENV USER=jovyan \
    UID=1000 \
    GID=100 \
    HOME=/workspace

USER root

# -------------------------------------------------------------------
# Base system packages (runtime only)
# -------------------------------------------------------------------
RUN dnf upgrade -y && dnf install -y \
    ca-certificates curl git git-lfs nano net-tools sudo wget graphviz file tree \
    podman skopeo fontconfig freetype nextcloud-client \
    htop openssh-clients procps-ng zsh dumb-init glibc-langpack-en \
    findutils which tar gzip bzip2 unzip hostname shadow-utils \
    && dnf clean all && rm -rf /var/cache/dnf

RUN groupadd -g 100 users 2>/dev/null || getent group 100
RUN useradd -m -u 1000 -g 100 -s /bin/bash jovyan && \
    grep -q '^jovyan:' /etc/subuid || echo 'jovyan:100000:65536' >> /etc/subuid && \
    grep -q '^jovyan:' /etc/subgid || echo 'jovyan:100000:65536' >> /etc/subgid && \
    mkdir -p /run/user/1000 && chown 1000:100 /run/user/1000 && chmod 700 /run/user/1000 && \
    echo "jovyan ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jovyan && \
    chmod 440 /etc/sudoers.d/jovyan && \
    git lfs install --system

# -------------------------------------------------------------------
# NVM and Node.js
# -------------------------------------------------------------------
ARG NVM_VERSION=v0.40.3
ARG NODE_VERSION=22.15.0

ENV NVM_DIR=/opt/nvm

RUN mkdir -p "${NVM_DIR}" && \
    curl -fsSL \
      "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" \
      | bash && \
    bash -c '. "${NVM_DIR}/nvm.sh" && nvm install "${NODE_VERSION}" && nvm alias default "${NODE_VERSION}"' && \
    chown -R jovyan:users "${NVM_DIR}"

ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:${PATH}"

RUN printf '\nexport NVM_DIR="/opt/nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' \
    >> /etc/bashrc

# -------------------------------------------------------------------
# code-server
# -------------------------------------------------------------------
ARG CODE_RELEASE=4.144.0
RUN mkdir -p /opt/code-server && \
    curl -fsSL \
      "https://github.com/coder/code-server/releases/download/v${CODE_RELEASE}/code-server-${CODE_RELEASE}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz --strip-components=1 -C /opt/code-server

ENV PATH="/opt/code-server/bin:${PATH}"

# -------------------------------------------------------------------
# Kubernetes / Dev tooling (pinned)
# -------------------------------------------------------------------
ARG KUBECTL_VERSION=v1.29.3
RUN curl -fsSL \
    https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

ARG TASK_VERSION=v3.41.0
RUN curl -fsSL \
    https://github.com/go-task/task/releases/download/${TASK_VERSION}/task_linux_${TARGETARCH}.tar.gz \
    | tar -xz -C /usr/local/bin task && chmod +x /usr/local/bin/task

ARG SKAFFOLD_VERSION=2.17.1
RUN curl -fsSL \
    https://storage.googleapis.com/skaffold/releases/v${SKAFFOLD_VERSION}/skaffold-linux-${TARGETARCH} \
    -o /usr/local/bin/skaffold && chmod +x /usr/local/bin/skaffold

ARG ORAS_VERSION=1.3.0
RUN curl -fsSL \
    https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${TARGETARCH}.tar.gz \
    | tar -xz -C /usr/local/bin oras && chmod +x /usr/local/bin/oras

# -------------------------------------------------------------------
# Python tooling
# -------------------------------------------------------------------
ARG CALRISSIAN_COMMIT=a95d87dd213d51b11faea7c6def4ced46d466a4a
COPY requirements-cwl-uml.txt /tmp/requirements-cwl-uml.txt

RUN pip install --no-cache-dir \
    -r /tmp/requirements-cwl-uml.txt \
    awscli \
    awscli-plugin-endpoint \
    "jhsingle-native-proxy>=0.0.9" \
    bash_kernel \
    tomlq \
    uv \
    cwltool \
    cwltest && \
    python -m bash_kernel.install

# Bash kernels detect a finished cell by their prompt. When ~/.bashrc activates a virtual
# environment, activating another one in a cell restores the pre-kernel prompt and the cell
# never finishes; keep venv activation away from the kernel prompt (terminals keep theirs).
RUN python -c "import json, pathlib; p = pathlib.Path('/usr/local/share/jupyter/kernels/bash/kernel.json'); spec = json.loads(p.read_text()); spec.setdefault('env', {})['VIRTUAL_ENV_DISABLE_PROMPT'] = '1'; p.write_text(json.dumps(spec))"

# Resolve the commit's cwltool/dependency requirements together, independently
# of the global CWL tools, rather than constraining cwl-utils to the old release.
RUN python -m venv /opt/calrissian-venv && \
    /opt/calrissian-venv/bin/pip install --no-cache-dir \
      "calrissian @ git+https://github.com/duke-gcb/calrissian.git@${CALRISSIAN_COMMIT}" && \
    /opt/calrissian-venv/bin/python -m pip check && \
    ln -s /opt/calrissian-venv/bin/calrissian /usr/local/bin/calrissian

# -------------------------------------------------------------------
# yq / jq
# -------------------------------------------------------------------
ARG YQ_VERSION=v4.45.1
RUN curl -fsSL \
    https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH} \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

ARG JQ_VERSION=jq-1.8.1
RUN curl -fsSL \
    https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-linux-${TARGETARCH} \
    -o /usr/local/bin/jq && chmod +x /usr/local/bin/jq

# -------------------------------------------------------------------
# hatch
# -------------------------------------------------------------------
ARG HATCH_VERSION=1.16.5
ENV HATCH_CONFIG=/home/jovyan/.config/hatch/config.toml \
    HATCH_DATA_DIR=/home/jovyan/.local/share/hatch \
    HATCH_CACHE_DIR=/home/jovyan/.cache/hatch
# The release launcher fetches its runtime on first use. Install Hatch and all
# its dependencies now, using the base image's native Python on either platform.
RUN python -m venv /opt/hatch-venv && \
    /opt/hatch-venv/bin/pip install --no-cache-dir "hatch==${HATCH_VERSION}" && \
    /opt/hatch-venv/bin/python -m pip check && \
    ln -s /opt/hatch-venv/bin/hatch /usr/local/bin/hatch && \
    install -d -o ${USER} -g users /home/jovyan/.config/hatch "${HATCH_DATA_DIR}" "${HATCH_CACHE_DIR}" && \
    install -o ${USER} -g users -m 644 /dev/null "${HATCH_CONFIG}"

# -------------------------------------------------------------------
# trivy
# -------------------------------------------------------------------
ARG TRIVY_VERSION=0.76.1
RUN case "${TARGETARCH}" in amd64) TRIVY_ARCH=64bit ;; arm64) TRIVY_ARCH=ARM64 ;; esac && \
    curl -fsSL \
    https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz \
    | tar -xz -C /usr/local/bin trivy

# -------------------------------------------------------------------
# GDAL
# -------------------------------------------------------------------
ARG GDAL_VER=3.12.1
# Keep runtime RPMs explicitly: the source-installed GDAL has no RPM dependency
# record, and removing proj-devel would otherwise also autoremove PROJ/data.
# Install and remove the build toolchain in this same layer to reclaim its size.
RUN set -eu && set -o pipefail && dnf install -y \
    cmake gcc-c++ ninja-build xz proj-devel proj-data proj && \
    dnf clean all && rm -rf /var/cache/dnf && \
    cd /tmp && \
    (curl -fsSL -o gdal-${GDAL_VER}.tar.xz https://download.osgeo.org/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.xz \
      || { rm -f gdal-${GDAL_VER}.tar.xz; curl -fsSL -o gdal-${GDAL_VER}.tar.gz https://download.osgeo.org/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.gz; }) && \
    if [ -f gdal-${GDAL_VER}.tar.xz ]; then \
        tar -xJf gdal-${GDAL_VER}.tar.xz; \
    else \
        tar -xzf gdal-${GDAL_VER}.tar.gz; \
    fi && \
    cd gdal-${GDAL_VER} && \
    mkdir build && cd build && \
    cmake -G Ninja ../ \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_INSTALL_LIBDIR=lib && \
    cmake --build . -- -j"$(nproc)" && \
    cmake --install . && \
    echo /usr/local/lib > /etc/ld.so.conf.d/gdal.conf && \
    echo /usr/local/lib64 >> /etc/ld.so.conf.d/gdal.conf && \
    ldconfig && \
    cd / && rm -rf /tmp/gdal-${GDAL_VER}* && \
    gdal-config --version && \
    ldd /usr/local/lib/libgdal.so > /tmp/gdal-runtime-libs && \
    ! grep -q 'not found' /tmp/gdal-runtime-libs && \
    dnf -y mark user proj proj-data xz && \
    awk '/=> \// {print $3}' /tmp/gdal-runtime-libs \
      | xargs -r rpm -qf --qf '%{NAME}\n' | sort -u | xargs -r dnf -y mark user && \
    dnf remove -y cmake gcc-c++ ninja-build proj-devel && \
    dnf clean all && rm -rf /var/cache/dnf /tmp/gdal-runtime-libs && \
    gdalinfo --version

# -------------------------------------------------------------------
# tomlq requires the Python yq package, whose console launcher shadows the
# pinned Mike Farah binary on Conda's PATH. Keep its modules and tomlq/xq
# launchers; replace only the conflicting command, without changing PATH.
# Prepare the default workspace for non-root tools after runtime installation,
# dropping the root-owned cache that build-isolated pip runs leave in HOME.
RUN ln -sf /usr/local/bin/yq /opt/conda/bin/yq && \
    rm -rf /workspace/.cache && \
    install -d -o ${USER} -g users /workspace

# -------------------------------------------------------------------
# Entrypoint
# -------------------------------------------------------------------
COPY nc-sync /usr/local/bin/nc-sync
RUN chmod 755 /usr/local/bin/nc-sync

COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Fedora's shadow-utils helpers are installed without setuid/file capabilities.
# Rootless Podman needs these narrowly scoped helpers to apply jovyan's ranges.
RUN test -x /usr/bin/newuidmap && test -x /usr/bin/newgidmap && \
    grep -q '^jovyan:' /etc/subuid && grep -q '^jovyan:' /etc/subgid && \
    chown root:root /usr/bin/newuidmap /usr/bin/newgidmap && \
    chmod 4755 /usr/bin/newuidmap /usr/bin/newgidmap

USER ${USER}

ENV GDAL_CONFIG=/usr/local/bin/gdal-config
ENV GDAL_DATA=/usr/local/share/gdal
ENV GDAL_DRIVER_PATH=/usr/local/lib/gdalplugins
ENV GDAL_OVERWRITE=YES

WORKDIR /workspace

EXPOSE 8888
ENTRYPOINT ["/opt/entrypoint.sh"]
