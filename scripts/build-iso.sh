#!/usr/bin/env bash
# Build the Arch Linux ARM installer ISO from source with Archboot's own tooling.
# Runs as root on an aarch64 Debian/Ubuntu host (GitHub's ubuntu-24.04-arm runner).
#  1. unpack the official Arch Linux ARM generic tarball into a chroot
#  2. update it, add the Archboot repository, install archboot-arm
#  3. run archboot-aarch64-iso.sh, which assembles the ISO from current ALARM packages
set -euo pipefail
ROOT=${ROOT:-/alarm}; OUT=${OUT:-$PWD/out}; MIRROR=${MIRROR:-http://os.archlinuxarm.org/os}
ARCHBOOT_FPR=5B7E3FB71B7F10329A1C03AB771DF6627EDF681F
mkdir -p "$OUT" "$ROOT"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libarchive-tools curl ca-certificates
curl -fL --retry 5 -o /tmp/base.tar.gz "$MIRROR/ArchLinuxARM-aarch64-latest.tar.gz"
curl -fL --retry 5 -o /tmp/base.tar.gz.md5 "$MIRROR/ArchLinuxARM-aarch64-latest.tar.gz.md5"
[ "$(md5sum /tmp/base.tar.gz | cut -d' ' -f1)" = "$(cut -d' ' -f1 /tmp/base.tar.gz.md5)" ] || { echo "md5 mismatch"; exit 1; }
bsdtar -xpf /tmp/base.tar.gz -C "$ROOT"
rm /tmp/base.tar.gz

mount --bind "$ROOT" "$ROOT"
mount --bind /dev "$ROOT/dev"; mount -t devpts devpts "$ROOT/dev/pts" || true
mount -t proc proc "$ROOT/proc"; mount -t sysfs sys "$ROOT/sys"; mount -t tmpfs tmpfs "$ROOT/tmp"
cleanup(){ set +e; umount -R "$ROOT" 2>/dev/null; }
trap cleanup EXIT
mv "$ROOT/etc/resolv.conf" "$ROOT/etc/resolv.conf.orig"; cp /etc/resolv.conf "$ROOT/etc/resolv.conf"

cat > "$ROOT/build.sh" <<INNER
set -euxo pipefail
pacman-key --init
pacman-key --populate archlinuxarm
pacman-key --keyserver hkps://keyserver.ubuntu.com --recv-keys $ARCHBOOT_FPR
pacman-key --lsign-key $ARCHBOOT_FPR
cat >> /etc/pacman.conf <<'CONF'

[archboot]
Server = https://pkg.archboot.com
CONF
pacman -Syu --noconfirm
pacman -S --noconfirm --needed archboot-arm
mkdir -p /build && cd /build
archboot-aarch64-iso.sh -g
find /build / -xdev -name '*.iso' -newer /build.sh 2>/dev/null | sort -u
INNER
chroot "$ROOT" /bin/bash /build.sh 2>&1 | tee "$OUT/build.log"

ISOS=$(find "$ROOT" -xdev -name '*.iso' -newer "$ROOT/build.sh" -not -path "$ROOT/proc/*" | sort -u)
[ -n "$ISOS" ] || { echo "no ISO produced"; exit 1; }
for f in $ISOS; do cp "$f" "$OUT/"; done
cd "$OUT"; sha256sum *.iso > SHA256SUMS; ls -lh
