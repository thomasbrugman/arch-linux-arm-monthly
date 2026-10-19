#!/usr/bin/env bash
# Supply a checkout of the pinned archiso revision as $1. No root/ARM required.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
UPSTREAM=${1:?path to archiso checkout}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -a "$UPSTREAM/configs/releng" "$TMP/profile"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pacman" <<'MOCK'
#!/bin/sh
# Retain upstream packages so profile adaptation can be tested on any host.
exit 0
MOCK
chmod +x "$TMP/bin/pacman"
printf '%s\n' 'Server = http://mirror.archlinuxarm.org/$arch/$repo' > "$TMP/mirrorlist"
PATH="$TMP/bin:$PATH" ARM_MIRRORLIST="$TMP/mirrorlist" bash "$ROOT/scripts/adapt-profile.sh" "$TMP/profile" > "$TMP/adapt.log" 2>&1
P="$TMP/profile"
grep -qx archlinuxarm-keyring "$P/packages.aarch64"
cmp "$P/pacman.conf" "$P/airootfs/etc/pacman.conf"
cmp "$TMP/mirrorlist" "$P/airootfs/etc/pacman.d/mirrorlist"
grep -qx 'SigLevel    = Required DatabaseOptional' "$P/airootfs/etc/pacman.conf"
grep -qx 'ExecStart=/usr/bin/pacman-key --populate archlinuxarm' "$P/airootfs/etc/systemd/system/pacman-init.service"
for service in getty@ serial-getty@; do
  grep -qx Requires=pacman-init.service "$P/airootfs/etc/systemd/system/$service.service.d/pacman-init.conf"
  grep -qx After=pacman-init.service "$P/airootfs/etc/systemd/system/$service.service.d/pacman-init.conf"
done
grep -Fq 'Server = ${mirror%%/}/\$arch/\$repo' "$P/airootfs/usr/local/bin/choose-mirror"
! grep -Fq '\$repo/os/\$arch' "$P/airootfs/usr/local/bin/choose-mirror"
grep -q 'test -s /usr/share/pacman/keyrings/archlinuxarm.gpg' "$P/airootfs/root/customize_airootfs.sh"
# The signing-key substitution is fail-closed if upstream changes the unit.
cp -a "$UPSTREAM/configs/releng" "$TMP/changed"
sed -i 's/--populate$/--populate changed/' "$TMP/changed/airootfs/etc/systemd/system/pacman-init.service"
if PATH="$TMP/bin:$PATH" ARM_MIRRORLIST="$TMP/mirrorlist" bash "$ROOT/scripts/adapt-profile.sh" "$TMP/changed" > "$TMP/negative.log" 2>&1; then
  echo 'changed upstream keyring unit was silently accepted' >&2
  exit 1
fi
echo 'Profile regression checks passed'
