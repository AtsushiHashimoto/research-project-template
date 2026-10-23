"""check-discipline-gates.py の部品（gh・git の読み取り、markdown の節、未確定の行の検査）。

単体では実行しない。述語の定義は check-discipline-gates.py とここだけ。
"""
import json
import re
import subprocess
import sys

KINDS = {"survey", "spec", "feature", "validation", "experiment", "bug", "docs", "refactor", "chore"}
SKIP_LABELS = {"out-of-date", "user-action"}
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
    return json.loads(run("gh", "issue", "view", str(n), "--json", "body,comments,createdAt,labels,state"))


def children(n):
    repo = run("gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip()
    out = run("gh", "api", f"repos/{repo}/issues/{n}/sub_issues", "--jq", ".[].number")
    kids = {}
    for k in out.split():
        d = issue(k)
        kids[k] = {"labels": {x["name"] for x in d["labels"]}, "state": d["state"].upper(), "d": d}
    return kids


def last_edited(n, d):
    repo = run("gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip()
    owner, name = repo.split("/", 1)
    q = ("query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo)"
         "{issue(number:$number){lastEditedAt createdAt}}}")
    j = json.loads(run("gh", "api", "graphql", "-f", f"query={q}", "-f", f"owner={owner}",
                       "-f", f"repo={name}", "-F", f"number={n}"))
    i = j["data"]["repository"]["issue"]
    return i.get("lastEditedAt") or i.get("createdAt") or d["createdAt"]


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


GOAL_RE = re.compile(r"^\s*-\s*\**(成功条件|negative の意味)\**\s*[:：]\s*(.+)$")


def goal_values(body):
    sec = section(body, "目標の状態")
    vals = {}
    for line in sec or []:
        m = GOAL_RE.match(line)
        if m:
            v = m.group(2).strip().strip("*").strip()
            blank = (not v) or re.fullmatch(r"<[^>]*>", v) or v in ("TBD", "未定")
            vals.setdefault(m.group(1), []).append(None if blank else v)
    return sec, vals


def item_name(text):
    t = re.split(r"→|->|解消済み|解消不能", text, maxsplit=1)[0]
    return t.strip().strip("*`").strip().rstrip("：:、,").strip()


def undecided(body):
    sec = section(body, "未確定")
    items = []
    for line in sec or []:
        m = re.match(r"^\s*[-*]\s+(.*\S)\s*$", line)
        if m:
            items.append(m.group(1))
    return items


def records(comments):
    names = set()
    for c in comments:
        b = c["body"].replace("\r", "")
        if b.startswith("## 未確定（記録）"):
            names |= {m.group(1).strip() for m in re.finditer(r"^- (.+)$", b, re.M)}
    return names


def path_on_main(p):
    return subprocess.run(["git", "cat-file", "-e", f"origin/main:{p}"], capture_output=True).returncode == 0


def check_undecided(task, d, kids):
    items = undecided(d["body"])
    if not items:
        ok("未確定: 節が無いか空（担当の検査は省く）")
    names = []
    for raw in items:
        name = item_name(raw)
        names.append(name)
        m = re.search(r"解消済み（→\s*#(\d+)\s*[,，、]\s*([^\s）]+?)(?=\s|）| §|$)", raw)
        if m:
            n, p = m.group(1), m.group(2)
            st = kids[n]["state"] if n in kids else issue(n)["state"].upper()
            if st != "CLOSED":
                fail(f"未確定「{name}」: 解消済みの根拠 #{n} が closed でない",
                     f"- {name} 解消済み（→ #<closed な issue>, <main にあるファイル>）")
            elif not path_on_main(p):
                fail(f"未確定「{name}」: 解消済みの根拠のファイル {p} が origin/main に無い"
                     f"（git cat-file -e origin/main:{p} が通らない）",
                     f"- {name} 解消済み（→ #{n}, <origin/main にあるファイル>）")
            else:
                ok(f"未確定「{name}」は解消済み（#{n}, {p}）")
            continue
        if re.search(r"解消不能（理由[:：]\s*\S", raw):
            ok(f"未確定「{name}」は解消不能（理由つき）")
            continue
        arrow = re.split(r"→|->", raw, maxsplit=1)
        if len(arrow) < 2:
            fail(f"未確定「{name}」に担当（→ の後の種類ラベルか #番号）が無い",
                 f"- {name} → <種類ラベル（例 validation）か #番号>")
            continue
        tokens = re.findall(r"#\d+|[a-z]+", re.split(r"[（(]", arrow[1].replace("*", "").replace("`", ""))[0])
        owners, bad = [], False
        for t in tokens:
            if t.startswith("#"):
                if t[1:] not in kids:
                    fail(f"未確定「{name}」の担当 {t} が task #{task} の子でない",
                         f"- {name} → #<task #{task} の子の番号>")
                    bad = True
                else:
                    owners.append(t[1:])
            elif t in KINDS:
                hit = [k for k, v in kids.items() if t in v["labels"]]
                if not hit:
                    fail(f"未確定「{name}」の担当 {t} の子が task #{task} に無い",
                         f"（/issue-create で {t} の子を作るか） - {name} → #<既存の子の番号>")
                    bad = True
                owners += hit
        if not tokens or (not owners and not bad):
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
    return names
