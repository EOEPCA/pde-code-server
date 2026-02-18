FROM docker.io/library/python:3.12.11-bookworm@sha256:bea386df48d7ee07eed0a1f3e6f9d5c0292c228b8d8ed2ea738b7a57b29c4470

ENV DEBIAN_FRONTEND=noninteractive \
    USER=jovyan \
    UID=1000 \
    GID=100 \
    HOME=/workspace

# -------------------------------------------------------------------
# Base system packages (runtime only)
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    git \
    nodejs \
    npm \
    nano \
    net-tools \
    sudo \
    wget \
    graphviz \
    file \
    tree \
    podman \
    skopeo \
    && apt-get remove -y yq

# -------------------------------------------------------------------
# Create user
# -------------------------------------------------------------------
#RUN groupadd -g ${GID} ${USER} && \
RUN useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER}

# -------------------------------------------------------------------
# code-server
# -------------------------------------------------------------------
ARG CODE_RELEASE=4.108.1
RUN mkdir -p /opt/code-server && \
    curl -fsSL \
      "https://github.com/coder/code-server/releases/download/v${CODE_RELEASE}/code-server-${CODE_RELEASE}-linux-amd64.tar.gz" \
      | tar -xz --strip-components=1 -C /opt/code-server

ENV PATH="/opt/code-server/bin:${PATH}"

# -------------------------------------------------------------------
# Kubernetes / Dev tooling (pinned, glibc-safe)
# -------------------------------------------------------------------
ARG KUBECTL_VERSION=v1.29.3
RUN curl -fsSL \
    https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

ARG TASK_VERSION=v3.41.0
RUN curl -fsSL \
    https://github.com/go-task/task/releases/download/${TASK_VERSION}/task_linux_amd64.tar.gz \
    | tar -xz -C /usr/local/bin task && chmod +x /usr/local/bin/task

ARG SKAFFOLD_VERSION=2.17.1
RUN curl -fsSL \
    https://storage.googleapis.com/skaffold/releases/v${SKAFFOLD_VERSION}/skaffold-linux-amd64 \
    -o /usr/local/bin/skaffold && chmod +x /usr/local/bin/skaffold

ARG ORAS_VERSION=1.3.0
RUN curl -fsSL \
    https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz \
    | tar -xz -C /usr/local/bin oras && chmod +x /usr/local/bin/oras


# -------------------------------------------------------------------
# Python tooling
# -------------------------------------------------------------------
ARG CALRISSIAN_VERSION=0.18.1
RUN pip install --no-cache-dir \
    awscli \
    awscli-plugin-endpoint \
    jhsingle-native-proxy>=0.0.9 \
    bash_kernel \
    tomlq \
    uv \
    cwltool \
    cwltest \
    "calrissian==${CALRISSIAN_VERSION}" && \
    python -m bash_kernel.install

# -------------------------------------------------------------------
# yq / jq (single source of truth)
# -------------------------------------------------------------------
ARG YQ_VERSION=v4.45.1
RUN curl -fsSL \
    https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq


ARG JQ_VERSION=jq-1.8.1
RUN curl -fsSL \
    https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-linux-amd64 \
    -o /usr/local/bin/jq && chmod +x /usr/local/bin/jq

# hatch (binary)
ARG HATCH_VERSION=1.16.2
RUN curl -fsSL \
    https://github.com/pypa/hatch/releases/download/hatch-v${HATCH_VERSION}/hatch-x86_64-unknown-linux-gnu.tar.gz \
    | tar -xz -C /usr/local/bin hatch && chmod +x /usr/local/bin/hatch

# trivy 
ARG TRIVY_VERSION=0.68.2
RUN curl -fsSL \
    https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.deb \
    -o /tmp/trivy.deb && \
    dpkg -i /tmp/trivy.deb && \
    rm /tmp/trivy.deb

#gdal
ARG GDAL_VER=3.12.1
# fetch, build, install
RUN apt-get install -qy \
    cmake ninja-build libproj-dev proj-data proj-bin; \
    set -e; \
    cd /tmp; \
    curl -fsSL -o gdal-${GDAL_VER}.tar.xz https://download.osgeo.org/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.xz \
      || curl -fsSL -o gdal-${GDAL_VER}.tar.gz https://download.osgeo.org/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.gz; \
    if [ -f gdal-${GDAL_VER}.tar.xz ]; then \
        tar -xJf gdal-${GDAL_VER}.tar.xz; \
    else \
        tar -xzf gdal-${GDAL_VER}.tar.gz; \
    fi; \
    cd gdal-${GDAL_VER}; \
    mkdir build && cd build; \
    cmake -G Ninja ../ \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local; \
    cmake --build . -- -j"$(nproc)"; \
    cmake --install .; \
    ldconfig; \
    rm -rf /tmp/gdal-${GDAL_VER}*; \
    rm -rf /var/lib/apt/lists/*; \
    gdal-config --version

#####

# -------------------------------------------------------------------
# Entrypoint
# -------------------------------------------------------------------
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