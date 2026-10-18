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
# free space on the runner image; the build needs several GB
rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache /usr/local/share/boost /usr/local/julia* 2>/dev/null || true
df -h / | tee -a "$OUT/build.log"
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
cleanup(){ set +e; df -h / | tee -a "$OUT/build.log"; du -sh "$ROOT" "$ROOT/container" 2>/dev/null | tee -a "$OUT/build.log"; umount -R "$ROOT" 2>/dev/null; }
trap cleanup EXIT
mv "$ROOT/etc/resolv.conf" "$ROOT/etc/resolv.conf.orig"; cp /etc/resolv.conf "$ROOT/etc/resolv.conf"

cat > "$ROOT/build.sh" <<INNER
set -euxo pipefail
retry() { for i in 1 2 3 4; do "\$@" && return 0; echo "retry \$i of: \$*"; sleep \$((i*20)); done; return 1; }
cat > /etc/pacman.d/mirrorlist <<'MIRRORS'
Server = http://fl.us.mirror.archlinuxarm.org/\$arch/\$repo
Server = http://nj.us.mirror.archlinuxarm.org/\$arch/\$repo
Server = http://ca.us.mirror.archlinuxarm.org/\$arch/\$repo
Server = http://de.mirror.archlinuxarm.org/\$arch/\$repo
Server = http://de4.mirror.archlinuxarm.org/\$arch/\$repo
Server = http://dk.mirror.archlinuxarm.org/\$arch/\$repo
Server = http://mirror.archlinuxarm.org/\$arch/\$repo
MIRRORS
sed -i -E '/^\[options\]/a DisableDownloadTimeout\nParallelDownloads = 3' /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinuxarm
retry pacman-key --keyserver hkps://keyserver.ubuntu.com --recv-keys $ARCHBOOT_FPR
pacman-key --lsign-key $ARCHBOOT_FPR
cat >> /etc/pacman.conf <<'CONF'

[archboot]
Server = https://pkg.archboot.com
Server = https://pkg.archboot.eu
Server = https://pkg.archboot.net
CONF
retry pacman -Syu --noconfirm
retry pacman -S --noconfirm --needed archboot-arm
pacman -Scc --noconfirm; df -h /
sed -i "s#^_NO_LOG=.*#_NO_LOG=/var/tmp/nolog.txt#" /usr/lib/archboot/common.sh
# systemd-nspawn cannot run inside our chroot (no systemd, no machine-id), so give Archboot a chroot-based stand-in
cat > /usr/local/bin/systemd-nspawn <<'SHIM'
#!/bin/bash
BINDS=(); DIR=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -q) shift;; --bind) BINDS+=("\$2"); shift 2;; -D) DIR="\$2"; shift 2;; *) break;;
  esac
done
MOUNTED=()
for m in proc sys dev; do
  mkdir -p "\$DIR/\$m"
  if ! mountpoint -q "\$DIR/\$m"; then
    case \$m in proc) mount -t proc proc "\$DIR/proc";; sys) mount -t sysfs sys "\$DIR/sys";; dev) mount --bind /dev "\$DIR/dev";; esac
    MOUNTED+=("\$m")
  fi
done
for b in "\${BINDS[@]}"; do mkdir -p "\$DIR\$b"; mount --bind "\$b" "\$DIR\$b"; done
[ -s "\$DIR/etc/resolv.conf" ] || cp -L /etc/resolv.conf "\$DIR/etc/resolv.conf" 2>/dev/null
chroot "\$DIR" "\$@"; rc=\$?
for b in "\${BINDS[@]}"; do umount "\$DIR\$b" 2>/dev/null; done
for m in "\${MOUNTED[@]}"; do umount -l "\$DIR/\$m" 2>/dev/null; done
exit \$rc
SHIM
chmod +x /usr/local/bin/systemd-nspawn
# Archboot builds the ISO inside a container filled with current ALARM packages
retry archboot-aarch64-create-container.sh /container
sed -i "s#^_NO_LOG=.*#_NO_LOG=/var/tmp/nolog.txt#" /container/usr/lib/archboot/common.sh
for m in dev proc sys; do mkdir -p /container/\$m; done
mount --bind /dev /container/dev; mount -t proc proc /container/proc; mount -t sysfs sys /container/sys
chroot /container /bin/bash -c 'cd /root && bash -x /usr/bin/archboot-aarch64-iso.sh -g; echo ISO-SCRIPT-EXIT=\$?; ls -l /root/*.iso /*.iso 2>/dev/null; find / -xdev -name "*.iso" 2>/dev/null'
echo "=== nolog tail ==="; tail -n 40 /container/var/tmp/nolog.txt; echo "=== end ==="
umount /container/dev /container/proc /container/sys || true
INNER
chroot "$ROOT" /bin/bash /build.sh 2>&1 | tee "$OUT/build.log"

ISOS=$(find "$ROOT/container" -xdev -name '*.iso' -not -path '*/proc/*' | sort -u)
[ -n "$ISOS" ] || { echo "no ISO produced"; exit 1; }
for f in $ISOS; do cp "$f" "$OUT/"; done
cd "$OUT"; sha256sum *.iso > SHA256SUMS; ls -lh
