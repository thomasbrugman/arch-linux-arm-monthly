#!/usr/bin/env python3
"""Drive a live root login and signed-package smoke test over QEMU serial."""
import base64
import pathlib
import re
import socket
import sys
import time

sock_path, log_path, script_path = sys.argv[1:]
deadline = time.monotonic() + 1450
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
while True:
    try:
        sock.connect(sock_path)
        break
    except (FileNotFoundError, ConnectionRefusedError):
        if time.monotonic() >= deadline:
            raise SystemExit('serial socket did not become ready')
        time.sleep(1)
sock.settimeout(5)
stage = 0
buffer = b''
with open(log_path, 'wb', buffering=0) as log:
    while time.monotonic() < deadline:
        try:
            data = sock.recv(65536)
        except socket.timeout:
            continue
        if not data:
            break
        log.write(data)
        buffer = (buffer + data)[-100000:]
        if b'SQUASHFS error' in buffer:
            raise SystemExit('SQUASHFS error in guest')
        plain = re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', buffer)
        if stage == 0 and b'archiso login:' in plain:
            sock.sendall(b'root\n')
            stage = 1
            buffer = b''
        elif stage == 1 and re.search(rb'[#%] ?$', plain.rstrip()):
            payload = base64.b64encode(pathlib.Path(script_path).read_bytes())
            sock.sendall(b"echo " + payload + b" | base64 -d > /tmp/test-live.sh; timeout 300 bash /tmp/test-live.sh || echo ARCHISO_PACKAGE_TEST_FAILED\n")
            stage = 2
            buffer = b''
        elif stage == 2:
            if b'ARCHISO_SIGNED_PACKAGE_OK' in buffer:
                print('BOOT AND SIGNED PACKAGE TEST OK')
                sys.exit(0)
            # Use a full line: the failure marker also occurs in the echoed command.
            if re.search(rb'(?:\r?\n)ARCHISO_PACKAGE_TEST_FAILED\r?\n', buffer):
                raise SystemExit('signed package test failed')
raise SystemExit('guest stopped or timed out before signed-package test passed')
