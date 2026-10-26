#!/usr/bin/env python3
"""Separate-process smoke tests. Build with swift build first. Loopback only."""

import json
from pathlib import Path
import select
import signal
import socket
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / ".build" / "debug"


def launch(name, *arguments):
    return subprocess.Popen(
        [str(BIN / name), *map(str, arguments)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def cleanup(process):
    if process.poll() is None:
        process.kill()
    process.communicate(timeout=3)


class LoopbackProcesses(unittest.TestCase):
    def server(self, duration=10):
        process = launch("MinMaxEchoServer", "--port", 0, "--duration-seconds", duration)
        self.addCleanup(cleanup, process)
        self.assertTrue(select.select([process.stdout], [], [], 5)[0], "server readiness timeout")
        line = process.stdout.readline().strip()
        self.assertTrue(line.startswith("listening host=127.0.0.1 port="), line)
        return process, int(line.rsplit("=", 1)[1])

    def run_client(self, *arguments):
        process = launch("MinMaxGameClient", *arguments)
        self.addCleanup(cleanup, process)
        output, errors = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, errors)
        return output, json.loads(output.splitlines()[-1])

    def test_separate_process_echo_rejection_and_sigterm(self):
        server, port = self.server()
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
            sender.sendto(b"invalid", ("127.0.0.1", port))
            sender.sendto(b"MMXP\x01\x00\x00\x00" + bytes(25), ("127.0.0.1", port))
            sender.sendto(b"MMXP\x01\x01\x00\x00" + bytes(24), ("127.0.0.1", port))
        output, summary = self.run_client(
            "--port", port, "--count", 8, "--interval-ms", 5, "--timeout-ms", 500
        )
        self.assertEqual(len([line for line in output.splitlines() if line.startswith("rtt ")]), 8)
        self.assertEqual(summary["sent"], 8)
        self.assertEqual(summary["received"], 8)
        self.assertEqual(summary["timedOut"], 0)
        self.assertEqual(summary["lossPercent"], 0)
        server.terminate()
        output, errors = server.communicate(timeout=3)
        self.assertEqual(server.returncode, 0, errors)
        self.assertIn("stopped echoed=8 rejected=3", output)
        # The process released its listening port on SIGTERM.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as replacement:
            replacement.bind(("127.0.0.1", port))

    def test_silent_endpoint_counts_timeout_loss(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as silent:
            silent.bind(("127.0.0.1", 0))
            _, summary = self.run_client(
                "--port", silent.getsockname()[1], "--count", 3,
                "--interval-ms", 5, "--timeout-ms", 20
            )
        self.assertEqual(summary["sent"], 3)
        self.assertEqual(summary["received"], 0)
        self.assertEqual(summary["timedOut"], 3)
        self.assertEqual(summary["cancelled"], 0)
        self.assertEqual(summary["lossPercent"], 100)

    def test_sigint_counts_pending_as_cancelled(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as silent:
            silent.bind(("127.0.0.1", 0))
            silent.settimeout(3)
            client = launch(
                "MinMaxGameClient", "--port", silent.getsockname()[1],
                "--count", 100, "--interval-ms", 1000, "--timeout-ms", 60000
            )
            self.addCleanup(cleanup, client)
            silent.recvfrom(64)  # first send proves signal handlers are installed
            client.send_signal(signal.SIGINT)
            output, errors = client.communicate(timeout=3)
        self.assertEqual(client.returncode, 0, errors)
        summary = json.loads(output.splitlines()[-1])
        self.assertGreater(summary["cancelled"], 0)
        self.assertEqual(summary["sent"], summary["cancelled"])
        self.assertEqual(summary["timedOut"], 0)
        self.assertNotIn("lossPercent", summary)

    def test_server_duration_exits_without_signal(self):
        server, _ = self.server(duration=1)
        output, errors = server.communicate(timeout=3)
        self.assertEqual(server.returncode, 0, errors)
        self.assertIn("stopped echoed=0 rejected=0", output)

    def test_invalid_arguments_exit_nonzero(self):
        client = launch("MinMaxGameClient", "--count", 0)
        self.addCleanup(cleanup, client)
        output, errors = client.communicate(timeout=3)
        self.assertEqual(client.returncode, 1)
        self.assertEqual(output, "")
        self.assertIn("--count must be an integer", errors)


if __name__ == "__main__":
    unittest.main(verbosity=2)
