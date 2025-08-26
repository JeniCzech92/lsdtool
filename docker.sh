#!/usr/bin/env bash
set -euo pipefail

# Builds and runs docker image with necessary tools

TAG="lsdtool-toolchain:local"

docker build --platform linux/amd64 -t "${TAG}" .
exec docker run --platform linux/amd64 --rm -it -v "$(pwd)":/opt/lsdtool --workdir /opt/lsdtool "${TAG}" bash
