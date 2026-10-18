# arch-linux-arm-monthly

An installer ISO for Arch Linux ARM (aarch64, UEFI), built from source on the 1st of every month and published as a GitHub release (tag `iso-YYYY.MM.DD`). Arch Linux ARM does not publish an ISO of its own.

## How it is built

The workflow `.github/workflows/iso.yml` runs `scripts/build-iso.sh` on GitHub's free `ubuntu-24.04-arm` runner at 03:00 UTC on the 1st (and on manual start). The script:

1. Downloads the official Arch Linux ARM generic aarch64 tarball and checks its md5 against the mirror.
2. Unpacks it into a chroot, populates the Arch Linux ARM keyring and runs `pacman -Syu`.
3. Adds the [Archboot](https://archboot.com/) package repository (its signing key is pinned by fingerprint `5B7E3FB71B7F10329A1C03AB771DF6627EDF681F`) and installs `archboot-arm`.
4. Runs `archboot-aarch64-iso.sh`, which assembles the ISO.

What is built here and what is reused: the ISO is assembled on each run from current Arch Linux ARM packages. The ISO tooling (the `archboot-arm` package and its scripts) is Archboot's work by Tobias Powalowski; this repo does not change it. The Arch Linux ARM tarball is only the build environment.

## Using the ISO

Boot it with UEFI and follow the Archboot setup menu. Archboot lists UTM, Parallels Desktop and VMware as supported VM hosts on Apple Silicon. It states that UTM's Apple Virtualization backend does not work with the aarch64 kernel, so use UTM's QEMU backend.

Not affiliated with Arch Linux ARM or Archboot.
