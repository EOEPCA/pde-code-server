FROM docker.io/ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN \
    apt-get update && \
    ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime && \
    echo "Etc/UTC" > /etc/timezone && \
    apt-get install -y \
    build-essential \
    curl \
    gcc \
    vim \
    tree \
    file \
    tzdata && \
    dpkg-reconfigure -f noninteractive tzdata

    

RUN \
    echo "**** install node repo ****" && \
    curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
    echo 'deb https://deb.nodesource.com/node_14.x jammy main' \
        > /etc/apt/sources.list.d/nodesource.list && \
    echo "**** install build dependencies ****" && \
    apt-get update && \
    apt-get install -y \
    nodejs

RUN \
    echo "**** install runtime dependencies ****" && \
    apt-get install -y \
    git \
    jq \
    libatomic1 \
    nano \
    net-tools \
    sudo \
    podman \
    wget \
    python3 \
    python3-pip 

RUN \
    echo "**** install code-server ****" && \
    if [ -z ${CODE_RELEASE+x} ]; then \
        CODE_RELEASE=$(curl -sX GET https://api.github.com/repos/coder/code-server/releases/latest \
        | awk '/tag_name/{print $4;exit}' FS='[""]' | sed 's|^v||'); \
    fi && \
    mkdir -p /app/code-server && \
    curl -o \
        /tmp/code-server.tar.gz -L \
        "https://github.com/coder/code-server/releases/download/v${CODE_RELEASE}/code-server-${CODE_RELEASE}-linux-amd64.tar.gz" && \
    tar xf /tmp/code-server.tar.gz -C \
        /app/code-server --strip-components=1 && \
    echo "**** patch 4.0.2 ****" && \
    if [ "${CODE_RELEASE}" = "4.0.2" ] && [ "$(uname -m)" !=  "x86_64" ]; then \
        cd /app/code-server && \
        npm i --production @node-rs/argon2; \
    fi && \
    echo "**** clean up ****" && \
    apt-get purge --auto-remove -y \
        build-essential \
        nodejs && \
    apt-get clean && \
    rm -rf \
        /config/* \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/* \
        /etc/apt/sources.list.d/nodesource.list

ENV USER=jovyan \
    UID=1001 \
    GID=100 \
    HOME=/workspace \
    PATH=/opt/conda/bin:/app/code-server/bin/:$PATH:/app/code-server/


RUN \
    echo "**** install conda ****" && \
    wget https://repo.anaconda.com/miniconda/Miniconda3-py310_23.3.1-0-Linux-x86_64.sh -O miniconda.sh -q && \
    sh miniconda.sh -b -p /opt/conda && \
    export PATH="/opt/conda/bin:$PATH" && \
    conda install -n base -c conda-forge mamba && \
    conda config --system --append channels conda-forge && \
    conda config --system --append channels terradue && \
    conda config --system --append channels eoepca && \
    conda config --system --append channels r && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    conda config --system --set channel_priority "flexible"


RUN \
    mamba install -n base cwltool cwl-wrapper==0.12.2 nodejs && \
    mamba clean -a

RUN \
    echo "**** install yq, aws cli ****" && \
    VERSION="v4.45.4"                                                                               && \
    BINARY="yq_linux_amd64"                                                                         && \
    wget --quiet https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -O - |\
    tar xz && mv ${BINARY} /usr/bin/yq                                                              && \
    /opt/conda/bin/pip3 install awscli                                                              && \
    /opt/conda/bin/pip3 install awscli-plugin-endpoint                                              

RUN \
    echo "**** install jupyter-hub native proxy ****" && \
    /opt/conda/bin/pip3 install jhsingle-native-proxy>=0.0.9 && \
    echo "**** install bash kernel ****" && \
    /opt/conda/bin/pip3 install bash_kernel && \
    /opt/conda/bin/python3 -m bash_kernel.install

RUN \
    echo "**** adds user jovyan ****" && \
    useradd -m -s /bin/bash -N -u $UID $USER 

COPY entrypoint.sh /opt/entrypoint.sh

RUN chmod +x /opt/entrypoint.sh

RUN chown -R jovyan:100 /opt/conda

RUN \
    echo "**** required by cwltool docker pull even if running with --podman ****" && \
    ln -s /usr/bin/podman /usr/bin/docker

# hatch download and installation
RUN curl -L https://github.com/pypa/hatch/releases/latest/download/hatch-x86_64-unknown-linux-gnu.tar.gz -o /tmp/hatch-x86_64-unknown-linux-gnu.tar.gz && \
 tar -xzf /tmp/hatch-x86_64-unknown-linux-gnu.tar.gz -C /tmp/ && \
 mv /tmp/hatch /usr/bin/hatch && \
 rm -f /tmp/hatch-x86_64-unknown-linux-gnu.tar.gz && \
 chmod +x /usr/bin/hatch 

RUN mkdir -p /workspace/ && chown -R jovyan:100 /workspace/
USER jovyan 

RUN  hatch --version

ENTRYPOINT ["/opt/entrypoint.sh"]

EXPOSE 8888
