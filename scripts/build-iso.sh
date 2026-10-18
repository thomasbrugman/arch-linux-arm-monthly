#!/usr/bin/env bash
# Host side (aarch64 Ubuntu runner): turn the official Arch Linux ARM tarball into a container,
# then run scripts/in-container.sh inside it. That script runs upstream archiso's mkarchiso.
set -euo pipefail
MIRROR=${MIRROR:-http://os.archlinuxarm.org/os}
OUT=${OUT:-$PWD/out}
mkdir -p "$OUT"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates
curl -fL --retry 5 -o /tmp/alarm.tar.gz "$MIRROR/ArchLinuxARM-aarch64-latest.tar.gz"
curl -fL --retry 5 -o /tmp/alarm.tar.gz.md5 "$MIRROR/ArchLinuxARM-aarch64-latest.tar.gz.md5"
[ "$(md5sum /tmp/alarm.tar.gz | cut -d' ' -f1)" = "$(cut -d' ' -f1 /tmp/alarm.tar.gz.md5)" ] || { echo "md5 mismatch"; exit 1; }
sudo docker import /tmp/alarm.tar.gz alarm-base
rm -f /tmp/alarm.tar.gz
sudo docker run --rm --privileged \
  -v "$PWD":/src:ro -v "$OUT":/out \
  alarm-base /bin/bash /src/scripts/in-container.sh 2>&1 | tee "$OUT/build.log"
ls -lh "$OUT"
