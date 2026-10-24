"""進捗一覧 web server のテストが共有する fixture（test_progress_*.py から import する。ファイル名が test で始まらないので単独では集められない）。"""

import copy
import datetime
import importlib
import importlib.util
import sys
from pathlib import Path

PROGRESS = Path(__file__).resolve().parents[1] / "progress"
sys.path.insert(0, str(PROGRESS))   # server.py が同じディレクトリの progress_* を import するため


cmd, gh, git, tree, pview, work, pclose = (importlib.import_module(m) for m in (
    "progress_cmd", "progress_gh", "progress_git", "progress_tree", "progress_view", "progress_work", "progress_close"))
_spec = importlib.util.spec_from_file_location("progress_server", PROGRESS / "server.py")
server = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(server)
server.log = lambda level, msg: None   # 失敗を起こすテストの stderr を汚さない

REPO = "o/r"
NOW = datetime.datetime(2026, 10, 24, 9, 0, tzinfo=datetime.timezone.utc).timestamp()   # JST 18 時
DAY = 86400
BASE = "refs/remotes/origin/main"


def iso(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ref(name, time, remote=False, oid=None):
    return {"refname": ("refs/remotes/origin/" if remote else "refs/heads/") + name, "name": name,
            "oid": oid or "oid-" + name + ("-r" if remote else ""), "time": int(time)}


def pr(num, head, state="OPEN", oid=None, fork=False):
    return {"number": num, "state": state, "url": f"https://x/pull/{num}", "headRefName": head,
            "headRefOid": oid or "pr-" + str(num), "isCrossRepository": fork}
SECTIONS = tree.label_sections((PROGRESS.parent / "setup-labels.sh").read_text(encoding="utf-8"))


def issue(num, labels=(), state="OPEN", parent=None, reason=None, title=None, parent_repo=REPO, label_total=None):
    return {"number": num, "title": title or f"t{num}", "state": state, "stateReason": reason,
            "url": f"https://x/{num}", "updatedAt": "2026-10-23T00:00:00Z", "createdAt": "2026-01-05T00:00:00Z",
            "labels": {"totalCount": label_total or len(labels), "nodes": [{"name": x} for x in labels]},
            "parent": {"number": parent, "repository": {"nameWithOwner": parent_repo}} if parent else None,
            "closedByPullRequestsReferences": {"totalCount": 0, "nodes": []}}


C = "CLOSED"
ISSUES = [
    issue(1, ["epic"]),
    issue(2, ["task"], parent=1),
    issue(12, ["bug"], parent=2),                          # fix/12-x → 作業中
    issue(13, ["feature"], parent=2),
    issue(14, ["feature", "user-action"], parent=2),       # 要対応
    issue(15, ["feature"], C, 2, "COMPLETED"),             # ブランチが残っている → 残骸
    issue(16, ["feature"], C, 2, "NOT_PLANNED"),
    issue(51, ["feature", "bug"], parent=2),               # 逸脱: 種類ラベル 2 個
    issue(756, ["task"], parent=1),
    issue(770, ["survey"], parent=756),                    # survey/756-i770 → 作業中
    issue(771, ["spec"], C, 756, "COMPLETED"),             # survey/756-i771 が残っている
    issue(30, ["epic"], parent=1),                         # sub-epic（逸脱ではない）
    issue(50, ["feature"], parent=1),                      # 逸脱: epic 直下の issue 層
    issue(80, ["task"], C, 1, "NOT_PLANNED"),              # 見送った task の配下
    issue(81, ["feature"], parent=80),                     # closed の親の下の open
    issue(82, ["feature"], C, 80, "COMPLETED"),
    issue(90, ["task"], parent=1),
    issue(91, ["experiment"], parent=90),
    issue(92, ["survey", "blocked"], parent=90),           # 先頭の段が blocked → 次の候補に出さない
    issue(95, ["task"], parent=1),
    issue(96, ["validation"], parent=95),
    issue(97, ["spec"], parent=95),
    issue(98, ["feature"], C, 95, "DUPLICATE"),            # 重複で閉じた → 見送りに数える                        # 次の候補（spec が validation より先）
    issue(110, ["task"], C, 1, "COMPLETED"),               # closed の task の open の子は候補にしない
    issue(111, ["feature"], parent=110),
    issue(120, ["task"], C, 1, "COMPLETED"),               # 全部 closed の task（194 §6 (a)）
    issue(121, ["feature"], C, 120, "COMPLETED"),
    issue(122, ["task"], C, 1, "COMPLETED"),               # 子の無い closed の task（(d)）
    issue(40, ["review-integrity"]),                       # 報告 issue（逸脱ではない）
    issue(41, ["enhancement"]),                            # テンプレート外のラベル
    issue(60, ["feature"], parent=12, parent_repo="other/repo"),   # 親が別 repo（番号は手元の #12 と同じ）
    issue(70, ["docs"], title="<script>alert(1)</script>"),
    issue(71, ["task"]),                                   # 逸脱: 親 epic の無い task
    issue(72, ["epic", "task"]),                           # 逸脱: 両方
    issue(73, ["feature", "user-action"], C, None, "COMPLETED"),   # closed は要対応に出さない
    issue(74, ["docs"], label_total=25),                   # 逸脱: labels の上限超え
    issue(130, ["epic"], C, None, "COMPLETED"),            # 全部 closed の根の epic（(b)）
    issue(131, ["feature"], C, 130, "COMPLETED"),
    issue(140, ["epic"], C, None, "COMPLETED"),            # closed の根の epic の下の open（(c)）
    issue(141, ["feature"], parent=140),
    issue(100, ["docs"], parent=101),                      # 親子の循環
    issue(101, ["docs"], parent=100),
]
BRANCHES = ["fix/12-x", "feature/15-old", "survey/756-i770", "survey/756-i771", "pre-task/2026-1", "main"]
FRESH = {"fix/12-x", "survey/756-i770"}                # 基準に無く NOW − 3 日（201 §9。#12・#770 が作業中）
REFS = [ref(b, NOW - (3 if b in FRESH else 100) * DAY) for b in BRANCHES]
UNMERGED = {r["refname"] for r in REFS if r["name"] in FRESH}
WORKTREES = [{"path": "/w/task756", "branch": "survey/756-i770", "prunable": False},
             {"path": "/w/gone", "branch": "fix/12-x", "prunable": True}]


def build(issues, **kw):
    """refs・PR なし、基準あり、now=NOW の既定で build する（引数で差し替える）。"""
    args = {"refs": [], "worktrees": [], "pulls": [], "base": BASE, "now": NOW, "unmerged": set()}
    args.update(kw)
    return tree.build(issues, REPO, SECTIONS, **args)


def built(**kw):
    return build(ISSUES, **{"refs": REFS, "worktrees": WORKTREES, "unmerged": UNMERGED, **kw})


# 201 §9 のカード用（ISSUES の手で数えた期待値を変えないので分ける）
def _cards():
    out = copy.deepcopy(ISSUES)
    stamp = {97: NOW - 40 * DAY, 95: NOW - 40 * DAY, 91: NOW - 30 * DAY, 92: NOW - 30 * DAY - 1}   # (h)
    for it in out:
        if it["number"] in stamp:
            it["updatedAt"] = iso(stamp[it["number"]])
        if it["number"] == 13:                         # C（closing keyword）の PR。A の #301 と合わせる
            it["closedByPullRequestsReferences"] = {"totalCount": 1, "nodes": [{"number": 300, "state": "MERGED", "url": "u"}]}
        if it["number"] == 12:                         # A と C の両方にある #302（重複を除く）
            it["closedByPullRequestsReferences"] = {"totalCount": 1, "nodes": [{"number": 302, "state": "MERGED", "url": "u"}]}
    m = issue(190, ["docs"])                           # (m) JST では翌日・前年
    m["updatedAt"], m["createdAt"] = "2026-10-20T15:30:00Z", "2025-12-31T00:00:00Z"
    return out + [
        issue(150, ["task"], parent=1), issue(151, ["feature"], C, 150, "COMPLETED"),          # (e)
        issue(160, ["epic"]), issue(161, ["task"], C, 160, "COMPLETED"),                       # (f)
        issue(170, ["epic"]), issue(171, ["task"], C, 170, "COMPLETED"), issue(172, ["feature"], parent=171),   # (j)
        issue(180, ["epic"]), issue(181, ["task"], parent=180), issue(182, ["feature"], C, 181, "COMPLETED"),  # (l)
        m]


CARD_ISSUES = _cards()
CARD_REFS = [ref("fix/12-x", NOW - 3 * DAY), ref("survey/756-i770", NOW - 3 * DAY),               # (g)
             ref("feature/13-y", NOW - 20 * DAY), ref("feature/14-z", NOW - 2 * DAY, oid="merged-14"),
             ref("feature/51-a", NOW - 14 * DAY), ref("feature/97-b", NOW - 14 * DAY - 1),
             ref("feature/96-c", NOW - 1 * DAY), ref("feature/96-c", NOW - 1 * DAY, remote=True)]
CARD_UNMERGED = {r["refname"] for r in CARD_REFS if r["name"] != "survey/756-i770"} - {"refs/heads/feature/96-c"}
CARD_PULLS = [pr(301, "feature/13-y", "MERGED"), pr(302, "fix/12-x", "MERGED"), pr(303, "survey/756-i770"),
              pr(304, "feature/14-z", "MERGED", oid="merged-14"),
              pr(310, "chore/no-number"), pr(311, "fix/12-evil", fork=True)]                       # (i)


def built_cards(**kw):
    return build(CARD_ISSUES, **{"refs": CARD_REFS, "worktrees": [], "unmerged": CARD_UNMERGED, "pulls": CARD_PULLS, **kw})
