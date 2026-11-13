"""voice dictation の受信側（scripts/voice/・.devcontainer/install-voice.sh）のテスト。

V1〜V4 は実際に listen するが PulseAudio は使わない（流し先を cat 等に差し替える）。
V5・V6 は設定ファイルの判定（install.sh が書いたものを install-voice.sh が読めるか）。
V7〜V9 は、同じ値を持つ複数のファイルが食い違っていないかの検査。
"""

import importlib.util
import json
import os
import re
import shlex
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("voice_recv", ROOT / "scripts" / "voice" / "recv.py")
recv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recv)
recv.log = lambda msg: None  # 記録の行でテストの出力を埋めない
INSTALL_VOICE = ROOT / ".devcontainer" / "install-voice.sh"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


class RecvTest(unittest.TestCase):
    def serve(self, sink_cmd):
        srv = recv.listen(port=0)
        thread = threading.Thread(target=recv.accept_loop, args=(srv, sink_cmd), daemon=True)
        thread.start()

        def cleanup():
            recv.stop(srv)
            thread.join(2)
            self.assertFalse(thread.is_alive(), "accept_loop が終わらない")

        self.addCleanup(cleanup)
        return srv.getsockname()[1]

    def wait_size(self, path, size):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if path.exists() and path.stat().st_size >= size:
                return
            time.sleep(0.02)

    def assert_closed_by_server(self, conn):
        try:
            self.assertEqual(conn.recv(1), b"")
        except ConnectionResetError:
            pass  # 読まれていないデータが残っていると、close は RST になる

    def send_and_collect(self, chunks):
        """chunks を 1 本の接続で送り、流し先（cat）が受け取ったバイト列を返す。"""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        out = Path(tmp.name) / "out.raw"
        port = self.serve("sh -c " + shlex.quote("cat > " + shlex.quote(str(out))))
        want = b"".join(chunks)
        with socket.create_connection(("127.0.0.1", port)) as c:
            for chunk in chunks:
                c.sendall(chunk)
        self.wait_size(out, len(want))
        return (out.read_bytes() if out.exists() else b""), want

    def test_v1_all_bytes_reach_the_sink_in_order(self):
        got, want = self.send_and_collect([os.urandom(70000), os.urandom(3)])
        self.assertEqual(got, want)

    def test_v2_burst_larger_than_half_a_second_is_not_dropped(self):
        # module-simple-protocol-tcp は 0.5 秒（16,000 バイト）を超えた分を捨てた。3 秒分を一度に送る
        got, want = self.send_and_collect([os.urandom(recv.BYTES_PER_SEC * 3)])
        self.assertEqual(len(got), len(want))
        self.assertEqual(got, want)

    def test_v3_missing_sink_closes_the_connection(self):
        # 流し先（pacat）を起動できないとき、送信側を待たせ続けず切る
        port = self.serve("/nonexistent/voice-sink")
        with socket.create_connection(("127.0.0.1", port), timeout=3) as c:
            c.sendall(b"x" * 10)
            self.assert_closed_by_server(c)

    def test_v4_second_sender_is_refused_while_first_is_connected(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        out = Path(tmp.name) / "out.raw"
        port = self.serve("sh -c " + shlex.quote("cat > " + shlex.quote(str(out))))
        with socket.create_connection(("127.0.0.1", port), timeout=3) as first:
            first.sendall(b"a" * 100)
            self.wait_size(out, 100)
            with socket.create_connection(("127.0.0.1", port), timeout=3) as second:
                self.assert_closed_by_server(second)  # すぐ切られる
            first.sendall(b"a" * 100)
        self.wait_size(out, 200)
        self.assertEqual(out.read_bytes(), b"a" * 200)  # 1 本目の音だけが、欠けずに届く


class OptionTest(unittest.TestCase):
    def check(self, text):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "options.env"
            if text is not None:
                path.write_bytes(text.encode())
            r = subprocess.run(["bash", str(INSTALL_VOICE), "--check", str(path)], capture_output=True, text=True)
            return r.returncode, r.stdout.strip()

    def test_v5_option_values(self):
        # 行末の CR（Windows の checkout）・引用符・export・前後の空白は許す
        for text in ("# c\nCLAUDE_VOICE=true\r\n", ' export CLAUDE_VOICE="true"  \n'):
            self.assertEqual(self.check(text), (0, "enabled"), repr(text))
        for text in (None, "# CLAUDE_VOICE=true\nOTHER=true\n"):
            self.assertEqual(self.check(text), (0, "disabled"), repr(text))
        # 読めない値を黙って「入れない」に倒さない（build が止まる）
        self.assertEqual(self.check("CLAUDE_VOICE=yes\n")[0], 2)

    def test_v6_install_sh_writes_what_install_voice_reads(self):
        # install.sh が書く heredoc の本文を取り出し、答えを入れて、Dockerfile が呼ぶのと同じ判定に通す
        body = re.search(r"cat > \.devcontainer/options\.env <<OPTIONS_EOF\n(.*?)\nOPTIONS_EOF\n", read("install.sh"), re.S)
        self.assertIsNotNone(body)
        self.assertIn("$CLAUDE_VOICE", body.group(1))
        for answer, want in (("true", "enabled"), ("false", "disabled")):
            self.assertEqual(self.check(body.group(1).replace("$CLAUDE_VOICE", answer) + "\n"), (0, want))
        dockerfile = read(".devcontainer/Dockerfile")
        self.assertIn("COPY .devcontainer/install-voice.sh .devcontainer/options.env* /tmp/devcontainer-voice/", dockerfile)
        self.assertIn("install-voice.sh --if-enabled /tmp/devcontainer-voice/options.env", dockerfile)


class ConsistencyTest(unittest.TestCase):
    def test_v7_port_matches_devcontainer_json_and_doc(self):
        port = str(recv.PORT)
        for kind in ("cpu", "gpu"):
            text = read(f".devcontainer/{kind}/devcontainer.json")
            conf = json.loads(re.sub(r"(?m)^\s*//.*$", "", text))
            # 手元の送信側は決まった番号に送るので、別の番号へずらされると届かない
            self.assertIs(conf["portsAttributes"][port]["requireLocalPort"], True, kind)
        doc = read(".claude/rules/template/optional-features.md")
        section = doc.split("### Claude Code の voice dictation")[1].split("\n### ")[0]
        numbers = set(re.findall(r"(?<!\d)\d{4,5}(?!\d)", section)) - {"16000"}
        self.assertEqual(numbers, {port})
        start = read("scripts/voice/start.sh")
        self.assertIn('recv.py" --print-port', start)
        self.assertNotIn(port, start)

    def test_v8_sink_and_socket_are_defined_once(self):
        start = read("scripts/voice/start.sh")
        self.assertIn(f"--device={recv.SINK} ", recv.SINK_CMD)
        self.assertIn('recv.py" --print-sink', start)
        self.assertNotIn(recv.SINK, start.split("set -euo pipefail")[1])  # コメントの図より下では名前を書かない
        # socket の場所は install-voice.sh が client.conf に書き、start.sh はそこから読む
        install = read(".devcontainer/install-voice.sh")
        m = re.search(r"^default-server = unix:(\S+)/native$", install, re.M)
        self.assertIsNotNone(m)
        self.assertEqual(start.count(m.group(1)), 0)
        self.assertIn("socket=$RUN/native", start)
        doc = read(".claude/rules/template/optional-features.md")
        self.assertIn(f"`{m.group(1)}/recv.log`", doc)

    def test_v9_installed_marker_is_the_same_file(self):
        marker = "/etc/pulse/client.conf.d/claude-voice.conf"
        for rel in (".devcontainer/install-voice.sh", ".devcontainer/post-start.sh", "scripts/voice/start.sh"):
            self.assertIn(marker, read(rel), rel)


if __name__ == "__main__":
    unittest.main()
