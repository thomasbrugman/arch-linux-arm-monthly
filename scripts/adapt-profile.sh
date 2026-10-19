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
: > /tmp/kept.txt
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

# 3. The profile pacman.conf above configures the BUILD, not the live system.
# Ship an explicit ARM config and mirrorlist in airootfs as well.
install -Dm644 "$P/pacman.conf" "$P/airootfs/etc/pacman.conf"
install -Dm644 "${ARM_MIRRORLIST:-/etc/pacman.d/mirrorlist}" "$P/airootfs/etc/pacman.d/mirrorlist"
# Never let upstream's mirror= override switch to the x86 repository URL layout.
sed -i 's#\\$repo/os/\\$arch#\\$arch/\\$repo#' "$P/airootfs/usr/local/bin/choose-mirror"

# The keyring directory is tmpfs on every live boot. Populate it there, not at
# image build time, and fail the build if upstream's unit changes underneath us.
unit="$P/airootfs/etc/systemd/system/pacman-init.service"
grep -qx 'ExecStart=/usr/bin/pacman-key --populate' "$unit"
sed -i 's#^ExecStart=/usr/bin/pacman-key --populate$#ExecStart=/usr/bin/pacman-key --populate archlinuxarm#' "$unit"
grep -qx 'ExecStart=/usr/bin/pacman-key --populate archlinuxarm' "$unit"
# Gate interactive login on successful keyring initialization (not just ordering).
for getty in getty@ serial-getty@; do
  mkdir -p "$P/airootfs/etc/systemd/system/$getty.service.d"
  cat > "$P/airootfs/etc/systemd/system/$getty.service.d/pacman-init.conf" <<'UNIT'
[Unit]
Requires=pacman-init.service
After=pacman-init.service
UNIT
done

# 4. only UEFI (releng's aarch64 mode); drop memtest entry that is x86 only
sed -i "s/^bootmodes=.*/bootmodes=('uefi.systemd-boot')/; /^           'uefi.systemd-boot')$/d" "$P/profiledef.sh"
rm -f "$P"/efiboot/loader/entries/*memtest*

# 4b. the memdisk initramfs hook only serves syslinux's x86 BIOS memdisk boot; its phram module and memdiskfind binary
#     do not exist on aarch64, and the build errors without removing it
sed -i 's/ memdisk / /' "$P/airootfs/etc/mkinitcpio.conf.d/archiso.conf"


# 4c. squashfs xz BCJ filters: releng offers x86 and arm64, and mksquashfs picks per block.
#     The Arch Linux ARM kernel has no x86 BCJ decoder (CONFIG_XZ_DEC_X86 is not set), so any
#     block stored with the x86 filter fails in the live system with
#     "SQUASHFS error: xz decompression failed". Restrict the filters to what the
#     Arch Linux ARM kernel decodes (arm, armthumb, arm64).
sed -i "s/'-Xbcj' 'x86,arm64'/'-Xbcj' 'arm,armthumb,arm64'/" "$P/profiledef.sh"
grep -q "'-Xbcj' 'arm,armthumb,arm64'" "$P/profiledef.sh"


# 6. console log level: Arch Linux ARM's kernel defaults to printing info-level messages on the
#    console, which keeps spamming the live TTY after boot (the x86_64 ISO is quiet there).
#    Cap console printk at warning level, like a normal install; boot output is unchanged.
sed -i '/^options / s/$/ loglevel=4/' "$P"/efiboot/loader/entries/*.conf

# 5. Arch Linux ARM's kernel package ships /boot/Image and the preset linux-aarch64 instead of
#    /boot/vmlinuz-linux and a pkgbase file; give mkarchiso the names it expects.
cat > "$P/airootfs/root/customize_airootfs.sh" <<'CUSTOM'
#!/usr/bin/env bash
set -eux
test -s /usr/share/pacman/keyrings/archlinuxarm.gpg
test -s /usr/share/pacman/keyrings/archlinuxarm-trusted
grep -q "^SigLevel    = Required DatabaseOptional$" /etc/pacman.conf
kver=$(ls /usr/lib/modules | head -n1)
cp /boot/Image /boot/vmlinuz-linux
echo linux > "/usr/lib/modules/$kver/pkgbase"
mkinitcpio -k "$kver" -g /boot/initramfs-linux.img
rm -f /boot/Image /boot/Image.gz /boot/initramfs-linux-aarch64*.img /boot/initramfs-linux-fallback.img
rm -rf /boot/dtbs
CUSTOM
sed -i 's#^file_permissions=(#file_permissions=(\n  ["/root/customize_airootfs.sh"]="0:0:755"#' "$P/profiledef.sh"
