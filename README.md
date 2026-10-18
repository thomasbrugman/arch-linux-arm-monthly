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

## Using the ISO

Boot it with UEFI. In UTM use the QEMU backend with UEFI, not Apple Virtualization. Then follow the usual Arch install guide or run `archinstall`.

Not affiliated with Arch Linux or Arch Linux ARM.
