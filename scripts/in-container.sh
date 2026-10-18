#!/usr/bin/env bash
# Runs inside an Arch Linux ARM container. Builds the ISO with upstream archiso (pinned) and its releng profile.
set -euxo pipefail
ARCHISO_REV=723da192226e1c9d5def9168f13332793c82a85e   # archiso v91
retry() { for i in 1 2 3 4; do "$@" && return 0; echo "retry $i of: $*"; sleep $((i*20)); done; return 1; }

cat > /etc/pacman.d/mirrorlist <<'MIRRORS'
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://de4.mirror.archlinuxarm.org/$arch/$repo
Server = http://dk.mirror.archlinuxarm.org/$arch/$repo
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://nj.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
MIRRORS
sed -i -E 's/^#?ParallelDownloads.*/ParallelDownloads = 3/; /^\[options\]/a DisableDownloadTimeout' /etc/pacman.conf
sed -i -E 's/^#?(DisableSandbox)/\1/; /^\[options\]/a DisableSandbox' /etc/pacman.conf || true
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinuxarm
retry pacman -Syu --noconfirm
retry pacman -S --noconfirm --needed base-devel git arch-install-scripts dosfstools e2fsprogs erofs-utils libarchive libisoburn mtools squashfs-tools grub gzip systemd-ukify python

# upstream archiso, pinned to a commit
git clone https://gitlab.archlinux.org/archlinux/archiso.git /archiso
git -C /archiso checkout "$ARCHISO_REV"
install -Dm755 /archiso/archiso/mkarchiso /usr/local/bin/mkarchiso

# upstream releng profile, with the Arch Linux ARM adaptations from adapt-profile.sh
cp -a /archiso/configs/releng /profile
bash /src/scripts/adapt-profile.sh /profile

mkdir -p /work /out
mkarchiso -v -w /work -o /out /profile
cd /out
sha256sum *.iso > SHA256SUMS
ls -l /out
