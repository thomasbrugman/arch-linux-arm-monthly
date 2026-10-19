#!/usr/bin/env python3
"""Exercise serial login, echoed commands, success/failure without QEMU."""
import pathlib
import socket
import subprocess
import tempfile
import threading
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ConsoleTest(unittest.TestCase):
    def run_guest(self, result):
        with tempfile.TemporaryDirectory() as tmp:
            path = tmp + '/serial.sock'
            server = socket.socket(socket.AF_UNIX)
            server.bind(path)
            server.listen(1)
            received = []

            def guest():
                conn, _ = server.accept()
                with conn:
                    conn.sendall(b'archiso login: ')
                    received.append(conn.recv(4096))
                    conn.sendall(b'root@archiso ~ # ')
                    command = conn.recv(16384)
                    received.append(command)
                    conn.sendall(command + b'\r\n')
                    conn.sendall(result)
                server.close()

            thread = threading.Thread(target=guest)
            thread.start()
            run = subprocess.run(['python3', str(ROOT / 'scripts/boot-console.py'), path,
                                  tmp + '/serial.log', str(ROOT / 'scripts/test-live.sh')],
                                 capture_output=True, timeout=10)
            thread.join(timeout=5)
            self.assertEqual(received[0], b'root\n')
            self.assertNotIn(b'ARCHISO_SIGNED_PACKAGE_OK', received[1])
            return run.returncode

    def test_success(self):
        self.assertEqual(self.run_guest(b'ARCHISO_SIGNED_PACKAGE_OK\r\n'), 0)

    def test_failure(self):
        self.assertNotEqual(self.run_guest(b'ARCHISO_PACKAGE_TEST_FAILED\r\n'), 0)

    def test_echo_is_not_success(self):
        self.assertNotEqual(self.run_guest(b''), 0)

    def test_squashfs_error(self):
        self.assertNotEqual(self.run_guest(b'SQUASHFS error: corrupt block\r\n'), 0)


if __name__ == '__main__':
    unittest.main()
