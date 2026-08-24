FROM ubuntu:24.04

ARG USERNAME=lzq
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN printf 'Acquire::ForceIPv4 "true";\n' \
    > /etc/apt/apt.conf.d/99force-ipv4 && \
    sed -i \
      -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.tuna.tsinghua.edu.cn/ubuntu|g' \
      -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.tuna.tsinghua.edu.cn/ubuntu|g' \
      /etc/apt/sources.list.d/ubuntu.sources

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf automake autotools-dev \
    bc bison build-essential \
    ca-certificates cmake curl \
    device-tree-compiler file flex libfl-dev \
    gawk gperf help2man \
    libgmp-dev libmpc-dev libmpfr-dev \
    libssl-dev libtool pkg-config \
    git make perl \
    python3 python3-dev python3-pip python3-venv \
    texinfo unzip xz-utils zlib1g-dev \
    rsync \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid ${GID} ${USERNAME} && \
    useradd --uid ${UID} --gid ${GID} \
            --create-home --shell /bin/bash ${USERNAME}

RUN mkdir -p /workspace/cva6 && \
    chown -R ${UID}:${GID} /workspace /home/${USERNAME}

ENV PATH=/workspace/cva6/tools/bin:/workspace/cva6/tools/verilator-v5.008/bin:/workspace/cva6/tools/spike/bin:${PATH}

WORKDIR /workspace/cva6
COPY cva6-env.sh /home/${USERNAME}/.cva6-env.sh

RUN printf '\n# CVA6 environment\nsource /home/%s/.cva6-env.sh\n' "${USERNAME}" \
    >> /home/${USERNAME}/.bashrc && \
    chown ${UID}:${GID} \
    /home/${USERNAME}/.bashrc \
    /home/${USERNAME}/.cva6-env.sh
    
USER ${USERNAME}

CMD ["/bin/bash"]