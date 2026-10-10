FROM quay.io/jupyter/base-notebook:python-3.12

# BuildKit supplies amd64 or arm64 for each target platform.
ARG TARGETARCH
RUN case "${TARGETARCH}" in amd64|arm64) ;; *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; esac

ENV DEBIAN_FRONTEND=noninteractive \
    USER=jovyan \
    UID=1001 \
    GID=100 \
    HOME=/workspace

USER root

# -------------------------------------------------------------------
# Base system packages (runtime only)
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    git \
    nano \
    net-tools \
    sudo \
    wget \
    graphviz \
    file \
    tree \
    podman \
    skopeo \
    openjdk-17-jdk-headless \
    nextcloud-desktop-cmd=3.11.0-1.1build4 \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -u 1001 ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER}

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
    >> /etc/bash.bashrc

# -------------------------------------------------------------------
# code-server
# -------------------------------------------------------------------
ARG CODE_RELEASE=4.138.0
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
ARG HATCH_VERSION=1.16.2
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
ARG TRIVY_VERSION=0.74.0
RUN case "${TARGETARCH}" in amd64) TRIVY_ARCH=64bit ;; arm64) TRIVY_ARCH=ARM64 ;; esac && \
    curl -fsSL \
    https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.deb \
    -o /tmp/trivy.deb && \
    dpkg -i /tmp/trivy.deb && \
    rm /tmp/trivy.deb

# -------------------------------------------------------------------
# GDAL
# -------------------------------------------------------------------
ARG GDAL_VER=3.12.1
RUN apt-get update && apt-get install -y \
    cmake g++ ninja-build xz-utils libproj-dev proj-data proj-bin && \
    rm -rf /var/lib/apt/lists/* && \
    set -e && \
    cd /tmp && \
    curl -fsSL -o gdal-${GDAL_VER}.tar.xz https://download.osgeo.org/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.xz \
      || curl -fsSL -o gdal-${GDAL_VER}.tar.gz https://download.osgeo.org/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.gz && \
    if [ -f gdal-${GDAL_VER}.tar.xz ]; then \
        tar -xJf gdal-${GDAL_VER}.tar.xz; \
    else \
        tar -xzf gdal-${GDAL_VER}.tar.gz; \
    fi && \
    cd gdal-${GDAL_VER} && \
    mkdir build && cd build && \
    cmake -G Ninja ../ \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local && \
    cmake --build . -- -j"$(nproc)" && \
    cmake --install . && \
    ldconfig && \
    cd / && rm -rf /tmp/gdal-${GDAL_VER}* && \
    gdal-config --version

# -------------------------------------------------------------------
# tomlq requires the Python yq package, whose console launcher shadows the
# pinned Mike Farah binary on Conda's PATH. Keep its modules and tomlq/xq
# launchers; replace only the conflicting command, without changing PATH.
# Prepare the default workspace for non-root tools after runtime installation.
RUN ln -sf /usr/local/bin/yq /opt/conda/bin/yq && \
    install -d -o ${USER} -g users /workspace

# -------------------------------------------------------------------
# Entrypoint
# -------------------------------------------------------------------
COPY nc-sync /usr/local/bin/nc-sync
RUN chmod 755 /usr/local/bin/nc-sync

COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

USER ${USER}

ENV GDAL_CONFIG=/usr/local/bin/gdal-config
ENV GDAL_DATA=/usr/local/share/gdal
ENV GDAL_DRIVER_PATH=/usr/local/lib/gdalplugins
ENV GDAL_OVERWRITE=YES

WORKDIR /workspace

EXPOSE 8888
ENTRYPOINT ["/opt/entrypoint.sh"]
