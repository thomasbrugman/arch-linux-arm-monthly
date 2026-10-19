# arch-linux-arm-monthly

A live and installer ISO for Arch Linux ARM (aarch64, UEFI) that works like the official x86_64 Arch ISO. It is built on the 1st of every month and published as a GitHub release (tag `iso-YYYY.MM.DD`). Arch Linux ARM does not publish an ISO of its own.

## How it is built

`.github/workflows/iso.yml` runs on GitHub's free `ubuntu-24.04-arm` runner at 03:00 UTC on the 1st (and on manual start):

1. `scripts/build-iso.sh` downloads the official Arch Linux ARM aarch64 tarball, checks its md5 and imports it as a Docker image.
2. `scripts/in-container.sh` runs in that image: it updates it, checks out [archiso](https://gitlab.archlinux.org/archlinux/archiso) at a pinned commit (v91, the same tool that builds the official x86_64 ISO) and runs `mkarchiso` on archiso's own `releng` profile.
3. `scripts/boot-test.sh` boots the resulting ISO in QEMU (aarch64, UEFI firmware) and only lets the release through after a live root login, successful ARM keyring initialization, repository synchronization and a signed-package reinstall with signature checking required.

## What is upstream and what is changed

Reused unchanged: archiso and the `releng` profile (boot menu via systemd-boot, the live environment, `archinstall`, the same package list). Packages come from the Arch Linux ARM repositories.

Changed, in `scripts/adapt-profile.sh` (the build log prints the result):

- Repositories: Arch Linux ARM (`core`, `extra`, `alarm`) instead of Arch Linux, and the live system's keyring is `archlinuxarm`.
- Packages: releng's aarch64 list minus anything Arch Linux ARM does not carry (the build log lists them), with `linux-aarch64` as the kernel.
- Kernel glue: Arch Linux ARM's kernel package ships `/boot/Image` rather than the layout Arch's kernels use, so a small `customize_airootfs.sh` renames it to `vmlinuz-linux` and builds the initramfs.
- Boot modes: UEFI only, the x86-only memtest entry is removed, and the `memdisk` initramfs hook (syslinux BIOS only) is dropped.
- Squashfs BCJ filters: releng lets mksquashfs pick between the x86 and arm64 xz filters per block, but the Arch Linux ARM kernel cannot decode the x86 filter (`CONFIG_XZ_DEC_X86` is not set), which showed up as `SQUASHFS error: xz decompression failed` on some files. The image is built with ARM filters only, and the boot test fails if any SQUASHFS error appears in the serial log.

## Using the ISO

Boot it with UEFI. Use the [Arch installation guide](https://wiki.archlinux.org/title/Installation_guide) for partitioning, mounting and general setup, with the ARM-specific differences below. The presence of `archinstall` on the ISO is not a guarantee that every guided-install path supports this ARM kernel/boot layout.

### Package signing and pacstrap

The live ISO includes `archlinuxarm-keyring` and initializes and populates the trusted `archlinuxarm` keyring on each boot. Console login waits for that service. It ships an ARM `/etc/pacman.conf` with `SigLevel = Required DatabaseOptional` and ARM mirrors (`$arch/$repo`, not x86 Arch's `$repo/os/$arch`). Database signatures are optional because Arch Linux ARM does not sign repository databases; package signatures remain required.

Before installing, connect to the network, check the clock with `timedatectl`, and check the keyring:

```sh
systemctl status pacman-init.service --no-pager
pacman-key --list-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
```

After mounting the target root at `/mnt` and its FAT32 EFI System Partition at `/mnt/boot`, install with:

```sh
pacstrap -P /mnt base linux-aarch64 linux-firmware archlinuxarm-keyring
```

Do **not** copy the standard x86 guide's `pacstrap -K` here: `-K` creates an empty target keyring (and implies `-G`, which disables copying the live keyring). Without `-K`/`-G`, pacstrap seeds the target with the live trusted keyring. `-P` also copies the ARM pacman configuration; the mirrorlist is copied by default. Add your editor, networking tools and other packages as needed. Continue with `genfstab`, `arch-chroot`, locale, timezone, users and network setup from the guide. In the installed system, keep signature checking enabled and confirm:

```sh
pacman-key --populate archlinuxarm
```

If using an older ISO and the live keyring is missing, first wait for or restart `pacman-init.service`, then run `pacman-key --populate archlinuxarm`. If the keyring package/files are missing, or trust errors persist, stop and use a corrected image or verify the keyring through an independent trusted source. Do not use `SigLevel = Never` as the installation workaround.

### UEFI bootloader on aarch64

The ISO's bootloader does not install one on the target disk. For a normal UEFI VM, either systemd-boot or GRUB works. Do not use the x86 `--target=x86_64-efi` or BIOS/i386-pc instructions.

- **systemd-boot:** mount the target ESP at `/boot`, run `bootctl --esp-path=/boot install` inside the chroot, and add a loader entry using `linux /Image` (Arch Linux ARM's EFI-stubbed kernel), the initramfs file actually generated by `mkinitcpio -P`, and `options root=UUID=<root-filesystem-UUID> rw`. The kernel and initramfs must both be on the ESP (or a correctly configured XBOOTLDR partition), not an inaccessible root filesystem. Do not assume Arch x86's `/vmlinuz-linux` filename; this kernel uses `/boot/Image`. For the common `/boot/initramfs-linux.img` output the entry is:

  ```ini
  title Arch Linux ARM
  linux /Image
  initrd /initramfs-linux.img
  options root=UUID=<root-filesystem-UUID> rw
  ```

  Check `/boot` after `mkinitcpio -P` and adjust the `initrd` filename if the preset uses a different name. Add `/boot/loader/loader.conf` with `default arch.conf` and put the entry in `/boot/loader/entries/arch.conf`. Keep enough free space on the ESP for kernel updates.

- **GRUB:** the target name is `arm64-efi`, **not** `aarch64-efi`. The `--efi-directory` must match the mounted ESP, which is `/boot` in this example (check `findmnt /boot` inside the chroot). Install `grub efibootmgr` in the target, then run `grub-install --target=arm64-efi --efi-directory=/boot --bootloader-id=GRUB` and `grub-mkconfig -o /boot/grub/grub.cfg`. Check that the generated config has a menu entry referencing `/boot/Image` (or `/Image` when `/boot` is a separate filesystem) and the generated initramfs. If it finds no kernel, stop and fix kernel detection/configuration before rebooting. For VM firmware that cannot retain an NVRAM entry, use `grub-install --target=arm64-efi --efi-directory=/boot --removable`, which installs the aarch64 fallback path `EFI/BOOT/BOOTAA64.EFI`; use this on the target ESP, not the installer media.

These examples cover plain, unencrypted root filesystems in UEFI VMs. Encryption, unusual storage and real ARM boards need their own kernel parameters and boot setup. Secure Boot signing is not configured by these commands.

### UTM on Apple Silicon

In UTM on Apple Silicon the Apple Virtualization backend works out of the box and is the fastest option. The QEMU backend also works, with two caveats seen on real hardware:

- Attach the ISO as a disk on the VirtIO (or NVMe) interface, not as a USB CD: with the ISO on a removable USB drive and the hypervisor enabled, the kernel can die right after the systemd-boot menu with `Synchronous Exception at 0x...` (a UTM/QEMU hypervisor issue with USB storage; it does not happen in emulation or with VirtIO-attached media). UTM cannot make a removable CD on VirtIO ("Device ... is not removable"), so add it as a disk: VM settings > Drives > New Drive > uncheck "Removable" > Interface: VirtIO > "Import..." and pick the ISO. The ISO is hybrid, so it boots from disk exactly like a dd'ed USB stick.
- Under pure emulation (hypervisor off) the default `cortex-a72` CPU model works; it is just much slower.

Not affiliated with Arch Linux or Arch Linux ARM.
