# arch-linux-arm-monthly

A live and installer ISO for Arch Linux ARM (aarch64, UEFI) that works like the official x86_64 Arch ISO. It is built on the 1st of every month and published as a GitHub release (tag `iso-YYYY.MM.DD`). Arch Linux ARM does not publish an ISO of its own.

## How it is built

`.github/workflows/iso.yml` runs on GitHub's free `ubuntu-24.04-arm` runner at 03:00 UTC on the 1st (and on manual start):

1. `scripts/build-iso.sh` downloads the official Arch Linux ARM aarch64 tarball, checks its md5 and imports it as a Docker image.
2. `scripts/in-container.sh` runs in that image: it updates it, checks out [archiso](https://gitlab.archlinux.org/archlinux/archiso) at a pinned commit (v91, the same tool that builds the official x86_64 ISO) and runs `mkarchiso` on archiso's own `releng` profile.
3. `scripts/boot-test.sh` boots the resulting ISO in QEMU (aarch64, UEFI firmware) and only lets the release through if the live system reaches its login prompt.

## What is upstream and what is changed

Reused unchanged: archiso and the `releng` profile (boot menu via systemd-boot, the live environment, `archinstall`, the same package list). Packages come from the Arch Linux ARM repositories.

Changed, in `scripts/adapt-profile.sh` (the build log prints the result):

- Repositories: Arch Linux ARM (`core`, `extra`, `alarm`) instead of Arch Linux, and the live system's keyring is `archlinuxarm`.
- Packages: releng's aarch64 list minus anything Arch Linux ARM does not carry (the build log lists them), with `linux-aarch64` as the kernel.
- Kernel glue: Arch Linux ARM's kernel package ships `/boot/Image` rather than the layout Arch's kernels use, so a small `customize_airootfs.sh` renames it to `vmlinuz-linux` and builds the initramfs.
- Boot modes: UEFI only, the x86-only memtest entry is removed, and the `memdisk` initramfs hook (syslinux BIOS only) is dropped.
- Squashfs BCJ filters: releng lets mksquashfs pick between the x86 and arm64 xz filters per block, but the Arch Linux ARM kernel cannot decode the x86 filter (`CONFIG_XZ_DEC_X86` is not set), which showed up as `SQUASHFS error: xz decompression failed` on some files. The image is built with ARM filters only, and the boot test fails if any SQUASHFS error appears in the serial log.

## Using the ISO

Boot it with UEFI, then follow the usual Arch install guide or run `archinstall`.

In UTM on Apple Silicon the Apple Virtualization backend works out of the box and is the fastest option. The QEMU backend also works, with two caveats seen on real hardware:

- Attach the ISO as a disk on the VirtIO (or NVMe) interface, not as a USB CD: with the ISO on a removable USB drive and the hypervisor enabled, the kernel can die right after the systemd-boot menu with `Synchronous Exception at 0x...` (a UTM/QEMU hypervisor issue with USB storage; it does not happen in emulation or with VirtIO-attached media). UTM cannot make a removable CD on VirtIO ("Device ... is not removable"), so add it as a disk: VM settings > Drives > New Drive > uncheck "Removable" > Interface: VirtIO > "Import..." and pick the ISO. The ISO is hybrid, so it boots from disk exactly like a dd'ed USB stick.
- Under pure emulation (hypervisor off) the default `cortex-a72` CPU model works; it is just much slower.

Not affiliated with Arch Linux or Arch Linux ARM.
