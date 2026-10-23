"""check-discipline-gates.py の部品（gh・git の読み取り、markdown の節、未確定の行の検査）。

単体では実行しない。述語の定義は check-discipline-gates.py とここだけ。
"""
import hashlib
import json
import re
import subprocess
import sys

KINDS = {"survey", "spec", "feature", "validation", "experiment", "bug", "docs", "refactor", "chore"}
# task-run.sh が飛ばす状態ラベルと同じ集合（担当がこれを持つと、その未確定は誰にも解消されない）
SKIP_LABELS = {"out-of-date", "user-action", "blocked"}
FAILS = []


def ok(msg):
    print(f"  ok   {msg}")


def fail(msg, *lines):
    FAILS.append(msg)
    print(f"!!! FAILED: {msg}")
    for line in lines:
        print(f"     書く行: {line}")


def run(*cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        print(f"!!! 検査が壊れた: {' '.join(cmd)} が失敗した: {p.stderr.strip()[:200]}")
        sys.exit(2)
    return p.stdout


def issue(n):
    return json.loads(run("gh", "issue", "view", str(n), "--json", "body,comments,createdAt,labels,state,stateReason"))


def children(n):
    repo = run("gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip()
    out = run("gh", "api", f"repos/{repo}/issues/{n}/sub_issues", "--jq", ".[].number")
    kids = {}
    for k in out.split():
        d = issue(k)
        kids[k] = {"labels": {x["name"] for x in d["labels"]}, "state": d["state"].upper(), "d": d}
    return kids


def goal_hash(body):
    """「## 目標の状態」節の sha256 の先頭 12 桁。goal ゲートの判定はこの値で本文と結びつける
    （編集時刻で見ると、未確定の行を書き換えただけで判定し直しになる）"""
    sec = section(body, "目標の状態") or []
    return hashlib.sha256("\n".join(x.rstrip() for x in sec).strip().encode()).hexdigest()[:12]


def norm(line):
    """装飾（** と `）を落とす。goal・未確定・仕様整合の行は、すべてこれを通してから照合する"""
    return line.replace("*", "").replace("`", "")


def section(text, prefix, exact=False):
    """`## <prefix>`（前方一致）から次の `## ` までの行。無ければ None"""
    lines, inside, found = [], False, False
    for line in text.replace("\r", "").split("\n"):
        if line.startswith("## "):
            head = line[3:].strip()
            inside = (head == prefix) if exact else head.startswith(prefix)
            found = found or inside
            continue
        if inside:
            lines.append(line)
    return lines if found else None


def latest(comments, heading):
    hits = [c for c in comments if any(x.strip() == heading or x.startswith(heading + " ")
                                        for x in c["body"].replace("\r", "").split("\n"))]
    return max(hits, key=lambda c: c["createdAt"]) if hits else None


GOAL_RE = re.compile(r"^\s*-\s*(成功条件|negative の意味)\s*[:：]\s*(.+)$")


def goal_values(body):
    sec = section(body, "目標の状態")
    vals = {}
    for line in sec or []:
        m = GOAL_RE.match(norm(line))
        if m:
            v = m.group(2).strip()
            blank = (not v) or re.fullmatch(r"<[^>]*>", v) or v in ("TBD", "未定")
            vals.setdefault(m.group(1), []).append(None if blank else v)
    return sec, vals


def item_name(text):
    t = re.split(r"→|->|解消済み|解消不能", norm(text), maxsplit=1)[0]
    return t.strip().rstrip("：:、,").strip()


def undecided(body):
    sec = section(body, "未確定")
    items = []
    for line in sec or []:
        # 項目は行頭の `-`・`*`・`N.` だけ。字下げした入れ子の箇条書きは項目の補足として読まない
        m = re.match(r"^(?:[-*]|\d+\.)\s+(.*\S)\s*$", line)
        if m:
            items.append(m.group(1))
    return items


def records(comments):
    """`## 未確定（記録）` の項目名 → 記録した担当（`- 名前 → 担当…`。担当の無い行は空）"""
    rec = {}
    for c in comments:
        b = c["body"].replace("\r", "")
        if b.startswith("## 未確定（記録）"):
            for m in re.finditer(r"^- (.+?)(?:\s+→\s+(.*))?$", b, re.M):
                rec.setdefault(m.group(1).strip(), (m.group(2) or "").split())
    return rec


def owner_tokens(raw):
    """→ の後の担当（#N か種類ラベル）。補足（括弧の中）と、解消済み・解消不能より後は見ない。
    装飾（** や `）は字句の抽出が読み飛ばすので norm() を通さない"""
    arrow = re.split(r"→|->", raw, maxsplit=1)
    if len(arrow) < 2:
        return None
    head = re.split(r"[（(]|解消済み|解消不能", arrow[1])[0]
    return re.findall(r"#\d+|[a-z]+", head)


def resolve(tokens, kids):
    """担当の字句 → 子の番号の一覧"""
    out = []
    for t in tokens:
        out += [t[1:]] if t.startswith("#") and t[1:] in kids else \
               [k for k, v in kids.items() if t in v["labels"]] if t in KINDS else []
    return out


def path_on_main(p):
    """origin/main にファイル（blob）としてあるか。ディレクトリ（tree）は根拠にならない"""
    r = subprocess.run(["git", "cat-file", "-t", f"origin/main:{p}"], capture_output=True, text=True)
    return r.returncode == 0 and r.stdout.strip() == "blob"


def check_resolved(task, name, raw, m, kids, rec):
    """`解消済み（→ #N, <path>）`: #N はその行の担当（行に無ければ記録の担当）の 1 つで closed、path は origin/main の blob"""
    n, p = m.group(1), m.group(2)
    toks = owner_tokens(raw.replace(m.group(0), "")) or rec.get(name, [])
    owners = resolve(toks, kids)
    if not owners:
        fail(f"未確定「{name}」: 担当が分からないので、解消済みの根拠 #{n} が担当かを照合できない",
             f"- {name} → <担当> 解消済み（→ #<担当の番号>, <origin/main にあるファイル>）")
    elif n not in owners:
        fail(f"未確定「{name}」: 解消済みの根拠 #{n} が担当（{' '.join('#' + k for k in owners)}）のどれでもない",
             f"- {name} 解消済み（→ #{owners[0]}, <origin/main にあるファイル>）")
    elif kids[n]["state"] != "CLOSED":
        fail(f"未確定「{name}」: 解消済みの根拠 #{n} が closed でない",
             f"- {name} 解消済み（→ #<closed な issue>, <main にあるファイル>）")
    elif not path_on_main(p):
        fail(f"未確定「{name}」: 解消済みの根拠のファイル {p} が origin/main に無い"
             f"（git cat-file -t origin/main:{p} が blob でない）",
             f"- {name} 解消済み（→ #{n}, <origin/main にあるファイル>）")
    else:
        ok(f"未確定「{name}」は解消済み（#{n}, {p}）")


def check_undecided(task, d, kids):
    items = undecided(d["body"])
    rec = records(d["comments"])
    if not items:
        ok("未確定: 節が無いか空（担当の検査は省く）")
    names = []
    for raw in items:
        name = item_name(raw)
        names.append(name)
        m = re.search(r"解消済み（→\s*#(\d+)\s*[,，、]\s*([^\s）]+?)(?=\s|）| §|$)", norm(raw))
        if m:
            check_resolved(task, name, norm(raw), m, kids, rec)
            continue
        if re.search(r"解消不能（理由[:：]\s*\S", raw):
            ok(f"未確定「{name}」は解消不能（理由つき）")
            continue
        tokens = owner_tokens(raw)
        if tokens is None:
            fail(f"未確定「{name}」に担当（→ の後の種類ラベルか #番号）が無い",
                 f"- {name} → <種類ラベル（例 validation）か #番号>")
            continue
        owners, bad = [], False
        for t in tokens:
            hit = resolve([t], kids)
            if t.startswith("#") and not hit:
                fail(f"未確定「{name}」の担当 {t} が task #{task} の子でない",
                     f"- {name} → #<task #{task} の子の番号>")
                bad = True
            elif not t.startswith("#") and t in KINDS and not hit:
                fail(f"未確定「{name}」の担当 {t} の子が task #{task} に無い",
                     f"（/issue-create で {t} の子を作るか） - {name} → #<既存の子の番号>")
                bad = True
            owners += hit
        if not owners and not bad:
            fail(f"未確定「{name}」の → の後に種類ラベルも #番号も無い",
                 f"- {name} → <種類ラベルか #番号>")
            continue
        skip = [f"#{k}({','.join(sorted(kids[k]['labels'] & SKIP_LABELS))})"
                for k in owners if kids[k]["labels"] & SKIP_LABELS]
        if skip:
            fail(f"未確定「{name}」の担当が自動処理で飛ばされる状態ラベル付き: {' '.join(skip)}",
                 f"（ラベルを外すか、担当を替える） - {name} → <別の担当>")
        elif owners and all(kids[k]["state"] == "CLOSED" for k in owners) and not bad:
            fail(f"未確定「{name}」の担当（{' '.join('#' + k for k in owners)}）がすべて closed なのに、"
                 "解消したかどうかが書かれていない（再照合）",
                 f"- {name} 解消済み（→ #{owners[0]}, <origin/main にある根拠のファイル>）",
                 f"- {name} 解消不能（理由: <なぜ解消できないか>）")
        elif not bad:
            ok(f"未確定「{name}」の担当: {' '.join('#' + k for k in owners)}")
    return [(name, owner_tokens(raw) or []) for name, raw in zip(names, items)]
