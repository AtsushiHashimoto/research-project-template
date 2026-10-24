"""子が 0 件の open の epic・task を html から close する、唯一の書き込みの経路（.spec/issues/201-progress-cards.md §6）。

server.py は Host（順 1）と path（順 2）を見てここを呼ぶだけ。`gh issue close` を含むのはこのファイルだけ。
"""

import json
import threading

import progress_gh
from progress_cmd import FetchError, run_raw

MAX_BODY = 1024
LOCK = threading.Lock()   # close は 1 本ずつ


def check_request(headers, host):
    """順 3〜5 の前半（ヘッダ）。通れば None、外れたら (コード, 理由)。"""
    origin = headers.get("Origin")
    if not origin or origin == "null" or origin != "http://" + (host or ""):
        return 403, "Origin がこのページと一致しない"
    media = (headers.get("Content-Type") or "").split(";")[0].strip().lower()
    if media != "application/json" or headers.get("X-Progress-Close") != "1":
        return 403, "Content-Type が application/json でないか、X-Progress-Close: 1 が無い"
    length = headers.get("Content-Length")
    if headers.get("Transfer-Encoding") is not None or length is None:
        return 411, "Content-Length が要る"
    if not (length.isascii() and length.isdigit()) or int(length) < 1:
        return 400, f"Content-Length が 1 以上の整数でない: {length[:20]!r}"
    if int(length) > MAX_BODY:
        return 413, f"本文は {MAX_BODY} バイトまで"
    return None


def parse_body(raw):
    """順 5 の後半。番号か (コード, 理由)。"""
    try:
        body = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return 400, "本文が JSON でない"
    num = body.get("number") if isinstance(body, dict) else None
    if type(num) is not int or num <= 0:     # bool は int の部分型なので type で見る
        return 400, "number は正の整数"
    return num


def close(number, repo, runner=run_raw):
    """順 7。成功なら None、失敗なら理由の文字列（stderr の先頭）。
    gh を実行できない・timeout（runner の FetchError）も理由にする。timeout では GitHub 側で
    close が通っている場合があるので、呼び出し側は「試みた」として扱う（順 8 の無効化）。"""
    try:
        code, _, err = runner(["gh", "issue", "close", str(number), "--repo", repo, "--reason", "not planned"])
    except FetchError as e:
        return f"{e}（GitHub 側で close されたかは不明。一覧を取り直して確かめる）"
    return None if code == 0 else (err.strip().splitlines() or [f"終了コード {code}"])[0]


def perform(number, repo, runner=run_raw):
    """順 6〜7。(コード, 応答の JSON, close を試みたか) を返す。"""
    with LOCK:
        try:
            st = progress_gh.fetch_issue_state(repo, number, runner)
        except FetchError as e:
            return 502, {"error": f"GitHub で状態を確かめられない（close していない）: {e}"}, False
        refused = (f"#{number} は issue として存在しない" if st is None
                   else f"#{number} は open でない" if st["state"] != "OPEN"
                   else f"#{number} は epic・task でない" if not {"epic", "task"} & set(st["labels"])
                   else f"#{number} には子が {st['subIssues']} 件ある（別 repo の子を含む）" if st["subIssues"]
                   else None)
        if refused:
            return 409, {"error": refused}, False
        why = close(number, repo, runner)
        if why is not None:
            return 502, {"error": f"gh issue close が失敗: {why}"}, True
        return 200, {"closed": number}, True
