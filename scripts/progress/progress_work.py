"""作業中・完了扱い・動きなし・異常・段の帯の規則（純関数。他の progress_* を import しない）。

規則の原本は .spec/issues/201-progress-cards.md §3-1・§3-3・§4。progress_tree と progress_view はここから使う。
"""

import datetime
import re

# task 単位の worktree を使う派生プロジェクトのブランチ名 <type>/<TASK>-i<N>（テンプレートの issue-start は作らない）。
# issue 単位の形 <type>/<N>-<slug> にも一致してしまうので先に当てる
TASK_BRANCH = re.compile(r"^[a-z][a-z-]*/(\d+)-i(\d+)$")
# pre-task/・pre-epic/ は /task-run・/epic-cycle の退避ブランチ（日付が番号に見える）
ISSUE_BRANCH = re.compile(r"^(?!pre-(?:task|epic)/)[a-z][a-z-]*/(\d+)(?:-|$)")
STEP_ORDER = ["survey", "spec", "feature", "validation", "experiment"]   # issue-hierarchy.md の既定の task 構成
DROPPED = {"NOT_PLANNED", "DUPLICATE"}
WORKING_DAYS = 14   # 「作業中」: main に無い tip がこの日数以内（ちょうどは含む）
STALE_DAYS = 30     # 「30日動きなし」: 自分の updatedAt がこの日数より前（ちょうどは付かない）
DAY = 86400


def branch_issue(name):
    """ブランチ名 → (issue 番号, task 番号 or None)。形に合わなければ None。"""
    m = TASK_BRANCH.match(name)
    if m:
        return int(m.group(2)), int(m.group(1))
    m = ISSUE_BRANCH.match(name)
    return (int(m.group(1)), None) if m else None


def unix(iso):
    """`Z` 付きの ISO 8601 → unix 秒。"""
    return datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()


def attach_prs(nodes, pulls):
    """§3-1: A（head ブランチ名）と C（closing keyword。node に既にある）を番号で重複を除いて合わせる。
    pulls が None（取れなかった）なら C だけ。戻り値は結び付かなかった open の PR の番号（None なら不明）。"""
    linked = {p["number"] for n in nodes.values() for p in n["prs"]}
    unlinked = []
    for pr in pulls or []:
        hit = None if pr.get("isCrossRepository") else branch_issue(pr["headRefName"])
        if hit and hit[0] in nodes:
            nodes[hit[0]]["prs"].append({k: pr[k] for k in ("number", "state", "url")})
            linked.add(pr["number"])
    for pr in pulls or []:
        if pr["state"] == "OPEN" and pr["number"] not in linked:
            unlinked.append(pr["number"])
    for n in nodes.values():
        by_number = {p["number"]: p for p in n["prs"]}
        n["prs"] = [by_number[k] for k in sorted(by_number, reverse=True)]
    return None if pulls is None else sorted(unlinked)


def fresh_tip(ref, unmerged, merged_oids, now):
    """§4-1 の「新しい tip」。ref は {refname, oid, time}。"""
    return (ref["refname"] in unmerged and ref["oid"] not in merged_oids
            and now - ref["time"] <= WORKING_DAYS * DAY)


def working(n, refs, unmerged, merged_oids, now):
    return n["state"] == "OPEN" and (any(p["state"] == "OPEN" for p in n["prs"])
                                     or any(fresh_tip(r, unmerged, merged_oids, now) for r in refs))


def last_commit(refs):
    return max((r["time"] for r in refs), default=None)


def completed_like(n):
    return n["state"] == "OPEN" and n["kind"] in ("epic", "task") and len(n["children"]) >= 1 \
        and all(c["state"] == "CLOSED" for c in n["_kids"])


def stale(n, now):
    return n["state"] == "OPEN" and now - unix(n["updatedAt"]) > STALE_DAYS * DAY


def anomaly(n):
    return n["state"] == "OPEN" and n["kind"] in ("epic", "task") and not n["children"]


def steps(n, nodes):
    """task: 段ごとの子の数と closed の数。他は None（epic は progress_view が集計する）。"""
    if n["kind"] != "task":
        return None
    kids = [nodes[c] for c in n["children"]]
    return [{"step": s, "total": sum(s in k["labels"] for k in kids),
             "closed": sum(s in k["labels"] and k["state"] == "CLOSED" for k in kids)} for s in STEP_ORDER]


def sum_steps(tasks):
    """§3-3 の epic の帯: 段を持つ task の数と、段が閉じた task の数。"""
    out = [{"step": s, "total": 0, "closed": 0} for s in STEP_ORDER]
    for t in tasks:
        for acc, st in zip(out, t["steps"]):
            if st["total"]:
                acc["total"] += 1
                acc["closed"] += st["closed"] == st["total"]
    return out


def classify(nodes, refs_of, unmerged, pulls, now, work_ok):
    """§4 の各キーを node に書く。refs_of は番号 → その issue のブランチの ref の list。"""
    # squash merge 済みの head は main に入ったとみなす（fork の PR の head は手元のブランチではない）
    merged_oids = {p["headRefOid"] for p in pulls or [] if p["state"] == "MERGED" and not p.get("isCrossRepository")}
    for n in nodes.values():
        n["_kids"] = [nodes[c] for c in n["children"]]
    for n in nodes.values():
        mine = refs_of.get(n["number"], [])
        n["working"] = working(n, mine, unmerged, merged_oids, now) if work_ok else None
        n["lastCommit"] = last_commit(mine)
        n["completedLike"] = completed_like(n)
        n["gone"] = n["state"] == "CLOSED" or n["completedLike"]
        n["stale"] = stale(n, now)
        n["anomaly"] = anomaly(n)
        n["steps"] = steps(n, nodes)
    for n in nodes.values():
        # 規則が再帰しないので、子が全部完了扱いの open の親は完了扱いにも異常にもならない（§4-2 の最後）
        n["childrenCompletedLike"] = (n["state"] == "OPEN" and n["kind"] in ("epic", "task") and not n["gone"]
                                      and bool(n["_kids"]) and all(c["gone"] for c in n["_kids"]))
        # task・epic だけに付ける（issue 層は対象外で None）。不明なら None
        n["workingBelow"] = below(n) if work_ok and n["kind"] in ("epic", "task") and n["state"] == "OPEN" else None
    for n in nodes.values():
        del n["_kids"]


def below(n):
    stack = list(n["_kids"])
    while stack:
        c = stack.pop()
        if c["working"]:
            return True
        stack.extend(c["_kids"])
    return False
