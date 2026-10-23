"""issue・ブランチ・worktree から進捗の木を組む（純関数。ネットワークも git も呼ばない）。

規則の原本は .spec/issues/176-progress-server.md §3-1。階層の規則は
.claude/rules/template/issue-hierarchy.md と labels.md、ラベルの集合は scripts/setup-labels.sh。
"""

import re

# task 単位の worktree を使う派生プロジェクトのブランチ名 <type>/<TASK>-i<N>（テンプレートの issue-start は作らない）。
# issue 単位の形 <type>/<N>-<slug> にも一致してしまうので先に当てる
TASK_BRANCH = re.compile(r"^[a-z][a-z-]*/(\d+)-i(\d+)$")
# pre-task/・pre-epic/ は /task-run・/epic-cycle の退避ブランチ（日付が番号に見える）
ISSUE_BRANCH = re.compile(r"^(?!pre-(?:task|epic)/)[a-z][a-z-]*/(\d+)(?:-|$)")
NEEDS_USER = {"user-action", "blocked"}
DROPPED = {"NOT_PLANNED", "DUPLICATE"}
STEP_ORDER = ["survey", "spec", "feature", "validation", "experiment"]   # issue-hierarchy.md の既定の task 構成


def label_sections(setup_labels_text):
    """setup-labels.sh の `# --- <見出し> ---` ごとのラベル名。見出しの先頭語（階層・種類・報告…）で引く。"""
    sections, cur = {}, None
    for line in setup_labels_text.splitlines():
        head = re.match(r"\s*# --- (\S+?)ラベル", line)
        if head:
            cur = sections.setdefault(head.group(1), set())
            continue
        item = re.match(r'\s*"([^"|]+)\|', line)
        if item and cur is not None:
            cur.add(item.group(1))
    return sections


def branch_issue(name):
    """ブランチ名 → (issue 番号, task 番号 or None)。形に合わなければ None。"""
    m = TASK_BRANCH.match(name)
    if m:
        return int(m.group(2)), int(m.group(1))
    m = ISSUE_BRANCH.match(name)
    return (int(m.group(1)), None) if m else None


def kind_of(labels):
    if "epic" in labels:
        return "epic"
    return "task" if "task" in labels else "issue"


def build(issues, repo, sections, branches=None, worktrees=None, git_error=None):
    """木を組む。branches/worktrees が None なら git が失敗したとみなし、作業中と次の候補を「不明」にする。
    sections に「種類」が無ければ（setup-labels.sh を読めない）ラベルに基づく検査を行わない。"""
    nodes = {}
    for it in issues:
        labels = [x["name"] for x in it["labels"]["nodes"]]
        prs = it["closedByPullRequestsReferences"]
        nodes[it["number"]] = n = {
            "number": it["number"], "title": it["title"], "state": it["state"],
            "stateReason": it.get("stateReason"), "url": it["url"], "updatedAt": it["updatedAt"],
            "labels": labels, "kind": kind_of(labels), "parent": None, "children": [],
            "branches": [], "worktrees": [], "taskBranches": [], "prs": prs["nodes"],
            "marks": [], "notes": [], "progress": None, "working": None,
        }
        if it["labels"]["totalCount"] > len(labels) or prs["totalCount"] > len(prs["nodes"]):
            n["marks"].append("一覧の上限（labels 20 / PR 10）を超えている")
        if "epic" in labels and "task" in labels:
            n["marks"].append("epic と task が両方付いている")

    roots = link_parents(issues, nodes, repo)
    if "種類" in sections:
        for n in nodes.values():
            check_hierarchy(n, nodes, sections)

    git_ok = branches is not None and worktrees is not None
    if git_ok:
        attach_work(nodes, branches, worktrees)
    for n in nodes.values():
        n["working"] = working(n) if git_ok else None
        if git_ok and n["state"] == "CLOSED" and (n["branches"] or n["worktrees"]):
            n["notes"].append("残骸（closed なのにブランチ・worktree が残っている）")

    for r in roots:
        progress(nodes, r)
    for n in nodes.values():
        if n["kind"] in ("epic", "task") and not n["children"]:
            n["notes"].append("子なし")
    return {"repo": repo, "nodes": nodes, "roots": roots,
            "summary": summarize(nodes, git_ok), "gitError": git_error}


def link_parents(issues, nodes, repo):
    """parent で子を張り、根の番号の list を返す。親が一覧に無いもの・循環の中のものも根にして印を付ける。"""
    roots = []
    for it in issues:
        n, p = nodes[it["number"]], it.get("parent")
        if p and p["repository"]["nameWithOwner"] == repo and p["number"] in nodes:
            n["parent"] = p["number"]
            nodes[p["number"]]["children"].append(n["number"])
        else:
            roots.append(n["number"])
            if p:
                n["marks"].append(f"親 {p['repository']['nameWithOwner']}#{p['number']} が一覧に無い")
    seen, stack = set(), list(roots)
    while stack:
        num = stack.pop()
        seen.add(num)
        stack.extend(nodes[num]["children"])
    for num in sorted(set(nodes) - seen):      # 根から辿れない＝親子が循環している。そこで切って根にする
        if num not in seen:
            n = nodes[num]
            nodes[n["parent"]]["children"].remove(num)
            n["parent"] = None
            n["marks"].append("親子が循環している")
            roots.append(num)
            stack = [num]
            while stack:
                c = stack.pop()
                seen.add(c)
                stack.extend(x for x in nodes[c]["children"] if x not in seen)
    return roots


def check_hierarchy(n, nodes, sections):
    kinds, report = sections.get("種類", set()), sections.get("報告", set())
    known = set().union(*sections.values())
    parent = nodes.get(n["parent"]) if n["parent"] else None
    if n["kind"] == "task" and (not parent or parent["kind"] != "epic"):
        n["marks"].append("task の親が epic でない")
    if n["kind"] != "issue":
        return
    mine = [x for x in n["labels"] if x in kinds]
    if parent and parent["kind"] == "epic":
        n["marks"].append("epic の直下に issue 層がある（task を挟む）")
    if len(mine) >= 2:
        n["marks"].append("種類ラベルが 2 個以上: " + ", ".join(mine))
    elif not mine:
        outside = [x for x in n["labels"] if x not in known]
        if any(x in report for x in n["labels"]):
            n["notes"].append("報告 issue")
        elif outside:
            n["notes"].append("テンプレート外のラベル: " + ", ".join(outside))
        else:
            n["notes"].append("種類ラベルなし")


def attach_work(nodes, branches, worktrees):
    for b in branches:
        hit = branch_issue(b)
        if hit and hit[0] in nodes:
            nodes[hit[0]]["branches"].append(b)
    by_branch = {b: n for n in nodes.values() for b in n["branches"]}
    for wt in worktrees:
        n = by_branch.get(wt["branch"] or "")
        if n and not wt["prunable"]:
            n["worktrees"].append(wt["path"])
    for b in branches:                         # task への集計は open の issue のブランチだけ（closed は残骸）
        hit = branch_issue(b)
        if hit and hit[1] in nodes and hit[0] in nodes and nodes[hit[0]]["state"] == "OPEN":
            nodes[hit[1]]["taskBranches"].append(b)


def working(n):
    return n["state"] == "OPEN" and bool(n["branches"] or n["worktrees"])


def dropped(n):
    return n["state"] == "CLOSED" and n["stateReason"] in DROPPED


def progress(nodes, num, under_dropped=False):
    """(完了, 分母, 見送り) を返し、子を持つノードに progress を書く。見送った親の配下は全部見送りに数える。"""
    n = nodes[num]
    gone = under_dropped or dropped(n)
    if not n["children"]:
        if gone:
            return 0, 0, 1
        return (1 if n["state"] == "CLOSED" else 0), 1, 0
    done, total, skipped = (sum(x) for x in zip(*(progress(nodes, c, gone) for c in n["children"])))
    n["progress"] = {"completed": done, "total": total, "notPlanned": skipped}
    return done, total, skipped


def step_key(n):
    steps = [STEP_ORDER.index(x) for x in n["labels"] if x in STEP_ORDER]
    return min(steps, default=len(STEP_ORDER)), n["number"]


def summarize(nodes, git_ok):
    opened = [n for n in nodes.values() if n["state"] == "OPEN"]
    needs = [n["number"] for n in opened if NEEDS_USER & set(n["labels"])]
    if not git_ok:
        return {"needsUser": needs, "working": None, "next": None}
    nxt = []
    for task in opened:                        # open な task ごとに、作業中の子が無ければ先頭の 1 件
        if task["kind"] != "task":
            continue
        kids = [nodes[c] for c in task["children"]]
        if any(k["working"] for k in kids):
            continue
        todo = sorted((k for k in kids if k["state"] == "OPEN" and k["kind"] == "issue"), key=step_key)
        if todo and todo[0]["number"] not in needs:   # 先頭が要対応ならそちらに出ている
            nxt.append(todo[0]["number"])
    return {"needsUser": needs, "working": [n["number"] for n in opened if n["working"]], "next": nxt}
