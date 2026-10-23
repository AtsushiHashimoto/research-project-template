"""外部コマンド（gh・git）を実行する共通部分。失敗は FetchError にそろえる。"""

import subprocess


class FetchError(Exception):
    """取得の失敗。メッセージは画面の帯とログにそのまま出す。"""


def run(argv, timeout=60):
    """コマンドを実行して stdout を返す。失敗は FetchError（終了コードと stderr の先頭を添える）。"""
    try:
        done = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace",
                              stdin=subprocess.DEVNULL, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FetchError(f"{argv[0]} を実行できない: {e}") from e
    if done.returncode != 0:
        head = done.stderr.strip().splitlines()[:3]
        raise FetchError(f"{' '.join(argv[:3])} が終了コード {done.returncode}: {' / '.join(head)}")
    return done.stdout
