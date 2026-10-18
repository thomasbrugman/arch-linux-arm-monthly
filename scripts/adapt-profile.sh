#!/usr/bin/env bash
# The only changes to archiso's releng profile. Everything is logged so the build log shows what differs from upstream.
set -euxo pipefail
P=${1:?profile dir}

# 1. package repositories: Arch Linux ARM instead of Arch Linux
cat > "$P/pacman.conf" <<'CONF'
[options]
HoldPkg     = pacman glibc
Architecture = aarch64
ParallelDownloads = 3
DisableDownloadTimeout
DisableSandbox
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[alarm]
Include = /etc/pacman.d/mirrorlist
CONF

# 2. package list: keep releng's list, but only what Arch Linux ARM carries; the kernel is linux-aarch64
pacman -Sy >/dev/null
: > /tmp/dropped.txt
grep -v '^#' "$P/packages.aarch64" | grep -v '^$' | sort -u | while read -r pkg; do
  [ "$pkg" = linux ] && continue
  if pacman -Si "$pkg" >/dev/null 2>&1; then echo "$pkg" >> /tmp/kept.txt; else echo "$pkg" >> /tmp/dropped.txt; fi
done
{ cat /tmp/kept.txt; echo linux-aarch64; echo archlinuxarm-keyring; } | sort -u > "$P/packages.aarch64"
echo "Packages in releng's aarch64 list that Arch Linux ARM does not carry (dropped):"; cat /tmp/dropped.txt
sed -i '/^stubble$/d' "$P/packages.aarch64"
cat "$P/bootstrap_packages" | head -0
# bootstrap tarball is not built here; keep file consistent
sed -i '/^archlinux-keyring$/d' "$P/bootstrap_packages" 2>/dev/null || true

# 3. keyring in the live system: Arch Linux ARM's
sed -i 's#/usr/bin/pacman-key --populate$#/usr/bin/pacman-key --populate archlinuxarm#' "$P/airootfs/etc/systemd/system/pacman-init.service"

# 4. only UEFI (releng's aarch64 mode); drop memtest entry that is x86 only
sed -i "s/^bootmodes=.*/bootmodes=('uefi.systemd-boot')/; /^           'uefi.systemd-boot')$/d" "$P/profiledef.sh"
rm -f "$P"/efiboot/loader/entries/*memtest* "$P"/efiboot/loader/entries/*speech* || true

# 4b. the memdisk initramfs hook only serves syslinux's x86 BIOS memdisk boot; its phram module and memdiskfind binary
#     do not exist on aarch64, and the build errors without removing it
sed -i 's/ memdisk / /' "$P/airootfs/etc/mkinitcpio.conf.d/archiso.conf"

# 5. Arch Linux ARM's kernel package ships /boot/Image and the preset linux-aarch64 instead of
#    /boot/vmlinuz-linux and a pkgbase file; give mkarchiso the names it expects.
cat > "$P/airootfs/root/customize_airootfs.sh" <<'CUSTOM'
#!/usr/bin/env bash
set -eux
kver=$(ls /usr/lib/modules | head -n1)
cp /boot/Image /boot/vmlinuz-linux
echo linux > "/usr/lib/modules/$kver/pkgbase"
mkinitcpio -k "$kver" -g /boot/initramfs-linux.img
rm -f /boot/Image /boot/Image.gz /boot/initramfs-linux-aarch64*.img /boot/initramfs-linux-fallback.img
rm -rf /boot/dtbs
CUSTOM
sed -i 's#^file_permissions=(#file_permissions=(\n  ["/root/customize_airootfs.sh"]="0:0:755"#' "$P/profiledef.sh"
