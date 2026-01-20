FROM docker.io/library/python:3.12.11-bookworm@sha256:bea386df48d7ee07eed0a1f3e6f9d5c0292c228b8d8ed2ea738b7a57b29c4470

ENV DEBIAN_FRONTEND=noninteractive \
    USER=jovyan \
    UID=1001 \
    GID=1001 \
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
    && apt-get remove -y yq \
 && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Create user
# -------------------------------------------------------------------
RUN groupadd -g ${GID} ${USER} && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USER} && \
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
# yq / jq (single source of truth)
# -------------------------------------------------------------------
ARG YQ_VERSION=v4.45.1
RUN curl -fsSL \
    https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq


# -------------------------------------------------------------------
# Python tooling
# -------------------------------------------------------------------
RUN pip install --no-cache-dir \
    awscli \
    awscli-plugin-endpoint \
    jhsingle-native-proxy>=0.0.9 \
    bash_kernel \
    tomlq \
    uv && \
    python -m bash_kernel.install


ARG JQ_VERSION=jq-1.8.1
RUN curl -fsSL \
    https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-linux-amd64 \
    -o /usr/local/bin/jq && chmod +x /usr/local/bin/jq

# hatch (binary)
ARG HATCH_VERSION=1.16.2
RUN curl -fsSL \
    https://github.com/pypa/hatch/releases/download/hatch-v${HATCH_VERSION}/hatch-x86_64-unknown-linux-gnu.tar.gz \
    | tar -xz -C /usr/local/bin hatch && chmod +x /usr/local/bin/hatch

# -------------------------------------------------------------------
# Entrypoint
# -------------------------------------------------------------------
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

USER ${USER}
WORKDIR /workspace

EXPOSE 8888
ENTRYPOINT ["/opt/entrypoint.sh"]