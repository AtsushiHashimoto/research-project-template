#!/usr/bin/env python3
"""issue ごとに本文・コメント・ラベル・状態・子を返す偽の gh（テスト専用）。

各テストの偽 gh（行形式 `番号:ラベル列:状態:題名:parent=<番号>`）は、§4 のゲートが使う
次の 3 つの呼び出しだけをここへ回す（`exec python3 "$FAKE_GH" "$@"`）:

  gh issue view N --json body,comments,createdAt[,labels,state]   → JSON（-q は使わない）
  gh api graphql … -F number=N                                    → lastEditedAt
  gh issue comment N --body B | --body-file F                     → コメントを足す

状態の置き場所:
  $FAKE_GH_ROWS        行形式のファイル（ラベル・状態・親）。各テストの issues.txt
  $FAKE_GH_DIR/N.json  本文・コメント・createdAt・lastEditedAt。無ければ既定値（DEFAULT_*）
  $FAKE_GH_DIR/comments.log  足したコメントの記録（テストが grep する）

★ 既定値は「ゲートを全部通る task」。ゲートを落とすテストは N.json を書いて上書きする。
★ 知らない呼び出しは大声で落とす（空出力で緑のまま通るのを防ぐ）。
"""
import json
import os
import sys

DEFAULT_BODY = """## 目標の状態

- 成功条件: 砂場の測定が 1 回通ること
- negative の意味: 通らなければ実装が壊れている
"""
DEFAULT_COMMENTS = [
    {"body": "## goal ゲート\n\n- G1b: PASS — 1 文の述語\n- G3: PASS — 残る\n- G4: PASS — 1 つ",
     "createdAt": "2020-01-02T00:00:00Z"},
    {"body": "## 判定\n\n結果: positive\n\n- 成功条件: 砂場の測定が 1 回通ること → 満たした",
     "createdAt": "2020-01-03T00:00:00Z"},
]


def die(msg):
    print(f"偽 gh (fake_gh.py): {msg}", file=sys.stderr)
    sys.exit(1)


def state_dir():
    d = os.environ.get("FAKE_GH_DIR") or die("FAKE_GH_DIR が無い")
    os.makedirs(d, exist_ok=True)
    return d


def rows():
    out = {}
    path = os.environ.get("FAKE_GH_ROWS", "")
    if not path or not os.path.exists(path):
        return out
    for line in open(path, encoding="utf-8"):
        parts = line.rstrip("\n").split(":")
        if len(parts) < 4 or not parts[0].isdigit():
            continue
        parent = parts[4][len("parent="):] if len(parts) > 4 else ""
        out[parts[0]] = {"labels": [x for x in parts[1].split(",") if x],
                         "state": parts[2], "title": parts[3], "parent": parent}
    return out


def load(n):
    f = os.path.join(state_dir(), f"{n}.json")
    if os.path.exists(f):
        d = json.load(open(f, encoding="utf-8"))
    else:
        d = {}
    d.setdefault("body", DEFAULT_BODY)
    d.setdefault("comments", [dict(c) for c in DEFAULT_COMMENTS])
    d.setdefault("createdAt", "2020-01-01T00:00:00Z")
    d.setdefault("lastEditedAt", None)
    r = rows().get(str(n))
    if r:
        d.setdefault("labels", r["labels"])
        d.setdefault("state", r["state"])
    d.setdefault("labels", [])
    d.setdefault("state", "OPEN")
    return d


def save(n, d):
    with open(os.path.join(state_dir(), f"{n}.json"), "w", encoding="utf-8") as fh:
        json.dump(d, fh, ensure_ascii=False)


def opt(args, name):
    for i, a in enumerate(args):
        if a == name and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(name + "="):
            return a[len(name) + 1:]
    return None


def main(a):
    if a[:2] == ["issue", "view"]:
        n, fields = a[2], opt(a, "--json") or die("--json が無い")
        if opt(a, "-q") is not None or opt(a, "--jq") is not None:
            die(f"-q は扱わない: {a}")
        d = load(n)
        out = {}
        for k in fields.split(","):
            if k == "labels":
                out[k] = [{"name": x} for x in d["labels"]]
            elif k in d:
                out[k] = d[k]
            else:
                die(f"未対応の欄 {k}")
        print(json.dumps(out, ensure_ascii=False))
        return
    if a[:2] == ["api", "graphql"]:
        n = None
        for i, x in enumerate(a):
            if x in ("-F", "-f") and a[i + 1].startswith("number="):
                n = a[i + 1].split("=", 1)[1]
        n or die(f"graphql に number が無い: {a}")
        d = load(n)
        print(json.dumps({"data": {"repository": {"issue": {
            "lastEditedAt": d["lastEditedAt"], "createdAt": d["createdAt"]}}}}))
        return
    if a[:2] == ["issue", "comment"]:
        n = a[2]
        body = opt(a, "--body")
        if body is None:
            f = opt(a, "--body-file") or die("--body も --body-file も無い")
            body = sys.stdin.read() if f == "-" else open(f, encoding="utf-8").read()
        d = load(n)
        # ★ 時刻は既存のどのコメント・本文の編集より後にする（「新しいか」の比較を通すため）
        times = [c["createdAt"] for c in d["comments"]] + [d["createdAt"], d["lastEditedAt"] or ""]
        last = max(times)
        d["comments"].append({"body": body, "createdAt": bump(last)})
        save(n, d)
        with open(os.path.join(state_dir(), "comments.log"), "a", encoding="utf-8") as fh:
            fh.write(f"=== #{n}\n{body}\n")
        return
    die(f"未対応の呼び出し: {' '.join(a)}")


def bump(t):
    """ISO 時刻を 1 秒進める（秒の桁だけ。テストの時刻は 2099 年まで）"""
    from datetime import datetime, timedelta
    dt = datetime.strptime(t, "%Y-%m-%dT%H:%M:%SZ") + timedelta(seconds=1)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


if __name__ == "__main__":
    main(sys.argv[1:])
