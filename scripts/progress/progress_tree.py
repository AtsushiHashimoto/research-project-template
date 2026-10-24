"""issue・ブランチ・worktree・PR から進捗の木を組む（純関数。ネットワークも git も呼ばない）。

規則の原本は .spec/issues/176-progress-server.md §3-1 と .spec/issues/201-progress-cards.md §4。階層の規則は
.claude/rules/template/issue-hierarchy.md と labels.md、ラベルの集合は scripts/setup-labels.sh。
"""

import re

from progress_work import (
    STALE_DAYS,
    STEP_ORDER,
    WORKING_DAYS,
    attach_prs,
    branch_issue,
    classify,
)


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


def kind_of(labels):
    if "epic" in labels:
        return "epic"
    return "task" if "task" in labels else "issue"


def build(issues, repo, sections, refs, worktrees, pulls, base, now, unmerged,
          git_error=None, pulls_error=None):
    """木を組む。refs/worktrees が None なら git が失敗、base が None なら基準のブランチが無い、pulls が None なら
    PR を取れなかったとみなし、作業中・配下で作業中・次の候補を「不明」（None）にする（201 §4 の work_ok）。
    unmerged は基準に無い ref の完全な refname の集合（git が失敗したら None）。now は取得を始めた unix 秒。どちらも省略不可。
    sections に「種類」が無ければ（setup-labels.sh を読めない）ラベルに基づく検査を行わない。"""
    nodes = {}
    for it in issues:
        labels = [x["name"] for x in it["labels"]["nodes"]]
        prs = it["closedByPullRequestsReferences"]
        nodes[it["number"]] = n = {
            "number": it["number"], "title": it["title"], "state": it["state"],
            "stateReason": it.get("stateReason"), "url": it["url"], "updatedAt": it["updatedAt"],
            "createdAt": it["createdAt"],
            "labels": labels, "kind": kind_of(labels), "parent": None, "children": [],
            "branches": [], "worktrees": [], "prs": [dict(p) for p in prs["nodes"]],
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

    git_ok = refs is not None and worktrees is not None
    refs_of = attach_work(nodes, refs, worktrees) if git_ok else {}
    unlinked = attach_prs(nodes, pulls)
    work_ok = git_ok and base is not None and pulls is not None
    classify(nodes, refs_of, unmerged, pulls, now, work_ok)
    for n in nodes.values():
        if git_ok and n["state"] == "CLOSED" and (n["branches"] or n["worktrees"]):
            n["notes"].append("残骸（closed なのにブランチ・worktree が残っている）")

    for r in roots:
        progress(nodes, r)
    rules = {"workingDays": WORKING_DAYS, "staleDays": STALE_DAYS, "base": base, "unlinkedOpenPrs": unlinked}
    return {"repo": repo, "nodes": nodes, "roots": roots, "now": now, "rules": rules,
            "summary": summarize(nodes, work_ok), "gitError": git_error, "pullsError": pulls_error}


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


def attach_work(nodes, refs, worktrees):
    """ブランチ名・worktree を node に付け、番号 → その issue の ref の list を返す。"""
    refs_of = {}
    for r in refs:
        hit = branch_issue(r["name"])
        if hit and hit[0] in nodes:
            refs_of.setdefault(hit[0], []).append(r)
            if r["name"] not in nodes[hit[0]]["branches"]:
                nodes[hit[0]]["branches"].append(r["name"])
    by_branch = {b: n for n in nodes.values() for b in n["branches"]}
    for wt in worktrees:
        n = by_branch.get(wt["branch"] or "")
        if n and not wt["prunable"]:
            n["worktrees"].append(wt["path"])
    return refs_of


def progress(nodes, num, under_dropped=False):
    """(完了, 分母, 見送り) を返し、子を持つノードに progress を書く。見送った親の配下は全部見送りに数える。"""
    n = nodes[num]
    gone = under_dropped or n["dropped"]
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


def summarize(nodes, work_ok):
    """要約の 3 群。完了扱いも closed と同じく外す（gone だけを見る。201 §4-2）。"""
    opened = [n for n in nodes.values() if not n["gone"]]
    needs = [n["number"] for n in opened if n["needs"]]
    if not work_ok:
        return {"needsUser": needs, "working": None, "next": None}
    nxt = []
    for task in opened:                        # open な task ごとに、作業中の子が無ければ先頭の 1 件
        if task["kind"] != "task":
            continue
        kids = [nodes[c] for c in task["children"]]
        if any(k["working"] for k in kids):
            continue
        todo = sorted((k for k in kids if not k["gone"] and k["kind"] == "issue"), key=step_key)
        if todo and todo[0]["number"] not in needs:   # 先頭が要対応ならそちらに出ている
            nxt.append(todo[0]["number"])
    return {"needsUser": needs, "working": [n["number"] for n in opened if n["working"]], "next": nxt}
