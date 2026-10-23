"""issue・ブランチ・worktree から進捗の木を組む（純関数。ネットワークも git も呼ばない）。

規則の原本は .spec/issues/176-progress-server.md §3-1。階層の規則は
.claude/rules/template/issue-hierarchy.md と labels.md、ラベルの集合は scripts/setup-labels.sh。
"""

import re

# 先に task 単位（<type>/<TASK>-i<N>）を当てる。issue 単位の形にも一致してしまうため
TASK_BRANCH = re.compile(r"^[a-z][a-z-]*/(\d+)-i(\d+)$")
ISSUE_BRANCH = re.compile(r"^[a-z][a-z-]*/(\d+)-")
NEEDS_USER = {"user-action", "blocked"}


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
    """木を組む。branches/worktrees が None なら git が失敗したとみなし、作業中を「不明」にする。"""
    kinds = sections.get("種類", set())
    report = sections.get("報告", set())
    known = set().union(*sections.values()) if sections else set()
    nodes = {}
    for it in issues:
        labels = [x["name"] for x in it["labels"]["nodes"]]
        nodes[it["number"]] = {
            "number": it["number"], "title": it["title"], "state": it["state"],
            "stateReason": it.get("stateReason"), "url": it["url"], "updatedAt": it["updatedAt"],
            "labels": labels, "kind": kind_of(labels), "parent": None, "children": [],
            "branches": [], "worktrees": [], "taskBranches": [],
            "prs": it["closedByPullRequestsReferences"]["nodes"], "marks": [], "notes": [],
            "progress": None, "working": None,
        }
        n = nodes[it["number"]]
        if it["labels"]["totalCount"] > len(labels) or it["closedByPullRequestsReferences"]["totalCount"] > len(n["prs"]):
            n["marks"].append("一覧の上限（labels 20 / PR 10）を超えている")
        if "epic" in labels and "task" in labels:
            n["marks"].append("epic と task が両方付いている")

    roots = []
    for it in issues:
        n, p = nodes[it["number"]], it.get("parent")
        same_repo = p and p["repository"]["nameWithOwner"] == repo
        if same_repo and p["number"] in nodes:
            n["parent"] = p["number"]
            nodes[p["number"]]["children"].append(n["number"])
        else:
            roots.append(n["number"])
            if p:
                n["marks"].append(f"親 {p['repository']['nameWithOwner']}#{p['number']} が一覧に無い")

    for n in nodes.values():
        check_hierarchy(n, nodes, kinds, report, known)

    git_ok = branches is not None and worktrees is not None
    if git_ok:
        attach_work(nodes, branches, worktrees)
    for n in nodes.values():
        n["working"] = working(n) if git_ok else None
        if git_ok and n["state"] == "CLOSED" and (n["branches"] or n["worktrees"]):
            n["notes"].append("残骸（closed なのにブランチ・worktree が残っている）")

    progress_all(nodes, roots)
    return {"repo": repo, "nodes": nodes, "roots": roots,
            "summary": summarize(nodes, git_ok), "gitError": git_error}


def check_hierarchy(n, nodes, kinds, report, known):
    parent = nodes.get(n["parent"]) if n["parent"] else None
    if n["kind"] == "task" and parent and parent["kind"] != "epic":
        n["marks"].append("task の親が epic でない")
    if n["kind"] == "issue":
        mine = [x for x in n["labels"] if x in kinds]
        if parent and parent["kind"] == "epic":
            n["marks"].append("epic の直下に issue 層がある（task を挟む）")
        if len(mine) >= 2:
            n["marks"].append("種類ラベルが 2 個以上: " + ", ".join(mine))
        elif not mine and not any(x in report for x in n["labels"]):
            outside = [x for x in n["labels"] if x not in known]
            n["notes"].append("テンプレート外のラベル: " + ", ".join(outside) if outside else "種類ラベルなし")


def attach_work(nodes, branches, worktrees):
    for b in branches:
        hit = branch_issue(b)
        if not hit or hit[0] not in nodes:
            continue
        nodes[hit[0]]["branches"].append(b)
        if hit[1] in nodes:
            nodes[hit[1]]["taskBranches"].append(b)
    by_branch = {b: n for n in nodes.values() for b in n["branches"]}
    for wt in worktrees:
        n = by_branch.get(wt["branch"] or "")
        if n and not wt["prunable"]:
            n["worktrees"].append(wt["path"])


def working(n):
    return n["state"] == "OPEN" and bool(n["branches"] or n["worktrees"])


def progress_all(nodes, roots):
    def walk(num):
        n = nodes[num]
        if not n["children"]:
            done = n["state"] == "CLOSED" and n["stateReason"] != "NOT_PLANNED"
            dropped = n["stateReason"] == "NOT_PLANNED"
            return (1 if done else 0, 0 if dropped else 1, 1 if dropped else 0)
        sums = [walk(c) for c in n["children"]]
        done, total, dropped = (sum(x) for x in zip(*sums))
        n["progress"] = {"completed": done, "total": total, "notPlanned": dropped}
        return done, total, dropped
    for r in roots:
        walk(r)
    for n in nodes.values():
        if n["kind"] in ("epic", "task") and not n["children"]:
            n["progress"] = None
            n["notes"].append("子なし")


def summarize(nodes, git_ok):
    opened = [n for n in nodes.values() if n["state"] == "OPEN"]
    needs = [n["number"] for n in opened if NEEDS_USER & set(n["labels"])]
    work = [n["number"] for n in opened if n["working"]] if git_ok else None
    nxt = []
    for n in opened:
        parent = nodes.get(n["parent"]) if n["parent"] else None
        if (n["kind"] == "issue" and not n["working"] and n["number"] not in needs
                and parent and parent["kind"] == "task" and parent["state"] == "OPEN"):
            nxt.append(n["number"])
    return {"needsUser": needs, "working": work, "next": nxt}
