"""進捗一覧 web server のテストが共有する fixture（test_progress_*.py から import する。ファイル名が test で始まらないので単独では集められない）。"""

import importlib
import importlib.util
import sys
from pathlib import Path

PROGRESS = Path(__file__).resolve().parents[1] / "progress"
sys.path.insert(0, str(PROGRESS))   # server.py が同じディレクトリの progress_* を import するため


cmd, gh, git, tree = (importlib.import_module(m) for m in ("progress_cmd", "progress_gh", "progress_git", "progress_tree"))
_spec = importlib.util.spec_from_file_location("progress_server", PROGRESS / "server.py")
server = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(server)
server.log = lambda level, msg: None   # 失敗を起こすテストの stderr を汚さない

REPO = "o/r"
SECTIONS = tree.label_sections((PROGRESS.parent / "setup-labels.sh").read_text(encoding="utf-8"))


def issue(num, labels=(), state="OPEN", parent=None, reason=None, title=None, parent_repo=REPO, label_total=None):
    return {"number": num, "title": title or f"t{num}", "state": state, "stateReason": reason,
            "url": f"https://x/{num}", "updatedAt": "2026-10-23T00:00:00Z",
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
    issue(40, ["review-integrity"]),                       # 報告 issue（逸脱ではない）
    issue(41, ["enhancement"]),                            # テンプレート外のラベル
    issue(60, ["feature"], parent=12, parent_repo="other/repo"),   # 親が別 repo（番号は手元の #12 と同じ）
    issue(70, ["docs"], title="<script>alert(1)</script>"),
    issue(71, ["task"]),                                   # 逸脱: 親 epic の無い task
    issue(72, ["epic", "task"]),                           # 逸脱: 両方
    issue(73, ["feature", "user-action"], C, None, "COMPLETED"),   # closed は要対応に出さない
    issue(74, ["docs"], label_total=25),                   # 逸脱: labels の上限超え
    issue(100, ["docs"], parent=101),                      # 親子の循環
    issue(101, ["docs"], parent=100),
]
BRANCHES = ["fix/12-x", "feature/15-old", "survey/756-i770", "survey/756-i771", "pre-task/2026-1", "main"]
WORKTREES = [{"path": "/w/task756", "branch": "survey/756-i770", "prunable": False},
             {"path": "/w/gone", "branch": "fix/12-x", "prunable": True}]


def built(**kw):
    args = {"branches": BRANCHES, "worktrees": WORKTREES}
    args.update(kw)
    return tree.build(ISSUES, REPO, SECTIONS, **args)
