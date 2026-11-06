FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git clang-14 gcc g++ gcc-multilib g++-multilib libc6-dev-i386 \
    python3 python3-pip python3-venv make file binutils perl pkg-config xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/ambuild-venv && \
    /opt/ambuild-venv/bin/pip install --no-cache-dir 'git+https://github.com/alliedmodders/ambuild.git'
ENV PATH="/opt/ambuild-venv/bin:${PATH}"
COPY extensions/System2/dependencies.lock.json extensions/System2/fetch-dependencies.py \
     extensions/System2/build-dependencies.sh /opt/system2-build/
RUN bash /opt/system2-build/build-dependencies.sh > /tmp/system2-dependencies.log 2>&1 \
    || { tail -100 /tmp/system2-dependencies.log; exit 1; }
RUN cp /tmp/system2-dependencies.log /opt/system2-deps/build.log
WORKDIR /workspace
