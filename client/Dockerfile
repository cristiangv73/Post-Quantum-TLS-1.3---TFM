FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV OPENSSL_CONF=/configs/openssl-oqs.cnf
ENV OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules

RUN apt-get update && apt-get install -y \
    openssl \
    libssl-dev \
    build-essential \
    cmake \
    ninja-build \
    git \
    ca-certificates \
    pkg-config \
    perl \
    iproute2 \
    iputils-ping \
    tcpdump \
    tshark \
    procps \
    curl \
    apache2-utils \
    python3 \
    python3-pip \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Instalar liboqs
RUN git clone --depth=1 https://github.com/open-quantum-safe/liboqs /opt/liboqs && \
    cmake -S /opt/liboqs -B /opt/liboqs/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON && \
    cmake --build /opt/liboqs/build && \
    cmake --install /opt/liboqs/build && \
    ldconfig

# Instalar oqs-provider
RUN git clone --depth=1 https://github.com/open-quantum-safe/oqs-provider /opt/oqs-provider && \
    cmake -S /opt/oqs-provider -B /opt/oqs-provider/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release && \
    cmake --build /opt/oqs-provider/build && \
    cmake --install /opt/oqs-provider/build && \
    ldconfig

WORKDIR /work
CMD ["/bin/bash"]
