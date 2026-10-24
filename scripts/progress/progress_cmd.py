"""外部コマンド（gh・git）を実行する共通部分。失敗は FetchError にそろえる。"""

import subprocess


class FetchError(Exception):
    """取得の失敗。メッセージは画面の帯とログにそのまま出す。"""


def run_raw(argv, timeout=60):
    """コマンドを実行して (終了コード, stdout, stderr) を返す。実行できなければ FetchError。
    終了コードで意味が分かれるもの（rev-parse の「無い」、gh の NOT_FOUND）に使う。"""
    try:
        done = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace",
                              stdin=subprocess.DEVNULL, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FetchError(f"{argv[0]} を実行できない: {e}") from e
    return done.returncode, done.stdout, done.stderr


def failure(argv, code, stderr):
    head = stderr.strip().splitlines()[:3]
    return FetchError(f"{' '.join(argv[:3])} が終了コード {code}: {' / '.join(head)}")


def run(argv, timeout=60):
    """コマンドを実行して stdout を返す。失敗は FetchError（終了コードと stderr の先頭を添える）。"""
    code, out, err = run_raw(argv, timeout)
    if code != 0:
        raise failure(argv, code, err)
    return out
