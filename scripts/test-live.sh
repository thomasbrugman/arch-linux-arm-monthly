#!/usr/bin/env bash
# Runs INSIDE the booted live ISO, not in the build container.
set -euxo pipefail
systemctl is-active --quiet pacman-init.service
pacman -Q archlinuxarm-keyring
test -s /usr/share/pacman/keyrings/archlinuxarm.gpg
pacman-key --list-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
# No SigLevel override: libalpm must require trusted package signatures.
siglevel=$(pacman-conf SigLevel)
for required in PackageRequired PackageTrustedOnly DatabaseOptional DatabaseTrustedOnly; do
  grep -qx "$required" <<< "$siglevel"
done
! grep -Eq 'PackageOptional|PackageNever|PackageTrustAll' <<< "$siglevel"
test "$(pacman-conf --repo-list | tr '\n' ' ')" = 'core extra alarm '
systemctl start systemd-networkd-wait-online.service
# -Sy alone only tests unsigned repository databases. Reinstall a small signed
# package with a fresh cache to exercise the live trust store and real mirrors.
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT
pacman -Sy --noconfirm
pacman -S --noconfirm --cachedir "$cache" archlinuxarm-keyring
pacman-key --populate archlinuxarm
# The marker is base64-encoded on the serial input, so an echoed command cannot
# accidentally satisfy the host-side success check.
echo ARCHISO_SIGNED_PACKAGE_OK
