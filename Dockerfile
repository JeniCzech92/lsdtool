# Stage 1: Build patchelf from source
FROM debian:forky-slim AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates build-essential curl tar pkg-config autoconf automake libtool

WORKDIR /tmp
RUN curl -L https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0.tar.bz2 | tar xjf - && \
    cd patchelf-0.18.0 && \
    ./configure && \
    make


# Stage 2: Actual runtime image
FROM debian:forky-slim

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates libc6:i386 libstdc++6:i386 binutils:i386 curl unzip file && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=755 --from=builder /tmp/patchelf-0.18.0/src/patchelf /usr/local/bin/patchelf

USER nobody
