#!/usr/bin/env bash
# Boot the built ISO in QEMU (aarch64, UEFI firmware) and wait for the live system's login prompt on the serial console.
set -euo pipefail
ISO=$(ls out/*.iso | head -n1)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-system-arm qemu-efi-aarch64 qemu-utils >/dev/null
cp /usr/share/AAVMF/AAVMF_VARS.fd /tmp/vars.fd 2>/dev/null || dd if=/dev/zero of=/tmp/vars.fd bs=1M count=64 2>/dev/null
ACCEL=tcg; [ -w /dev/kvm ] && ACCEL=kvm
echo "qemu accel: $ACCEL"
rm -f /tmp/archiso-serial.sock /tmp/serial.log
trap 'kill "${Q:-}" 2>/dev/null || true' EXIT
timeout 1500 qemu-system-aarch64 -machine virt,accel=$ACCEL -cpu max -smp 4 -m 3G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd \
  -drive if=pflash,format=raw,file=/tmp/vars.fd \
  -drive if=none,id=cd,format=raw,media=cdrom,readonly=on,file="$ISO" -device virtio-scsi-pci -device scsi-cd,drive=cd \
  -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
  -display none -serial unix:/tmp/archiso-serial.sock,server=on,wait=off -monitor none &
Q=$!
if python3 scripts/boot-console.py /tmp/archiso-serial.sock /tmp/serial.log scripts/test-live.sh; then
  tail -c 1500 /tmp/serial.log | tr -d '\r'
else
  echo "BOOT/PACKAGE TEST FAILED. Serial log tail:"
  tr -d '\r' < /tmp/serial.log | tail -n 80
  exit 1
fi
