#!/usr/bin/env bash
# Boot the built ISO in QEMU (aarch64, UEFI firmware) and wait for the live system's login prompt on the serial console.
set -uo pipefail
ISO=$(ls out/*.iso | head -n1)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-system-arm qemu-efi-aarch64 qemu-utils >/dev/null
cp /usr/share/AAVMF/AAVMF_VARS.fd /tmp/vars.fd 2>/dev/null || dd if=/dev/zero of=/tmp/vars.fd bs=1M count=64 2>/dev/null
ACCEL=tcg; [ -w /dev/kvm ] && ACCEL=kvm
echo "qemu accel: $ACCEL"
timeout 1500 qemu-system-aarch64 -machine virt,accel=$ACCEL -cpu max -smp 4 -m 3G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd \
  -drive if=pflash,format=raw,file=/tmp/vars.fd \
  -drive if=none,id=cd,format=raw,media=cdrom,readonly=on,file="$ISO" -device virtio-scsi-pci -device scsi-cd,drive=cd \
  -nographic -serial file:/tmp/serial.log -monitor none &
Q=$!
for i in $(seq 1 300); do
  sleep 5
  if grep -a -q "archiso login:" /tmp/serial.log 2>/dev/null; then
    if grep -a -q "SQUASHFS error" /tmp/serial.log; then
      echo "BOOT reached login prompt but the serial log contains SQUASHFS errors:"; grep -a "SQUASHFS error" /tmp/serial.log | sort | uniq -c | sort -rn | head; kill $Q; exit 1
    fi
    echo "BOOT OK after ~$((i*5))s"; kill $Q; tail -c 1500 /tmp/serial.log | tr -d '\r'; exit 0; fi
  kill -0 $Q 2>/dev/null || break
done
kill $Q 2>/dev/null
echo "BOOT FAILED. Serial log tail:"; tr -d '\r' < /tmp/serial.log | tail -n 60
exit 1
