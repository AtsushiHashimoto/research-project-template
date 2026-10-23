"""手元の git からブランチと worktree を読む（fetch はしない）。

GitHub の取得とは失敗の仕方が違うので別にしてある。ここが失敗しても木は出し、
「作業中」の列だけを不明にする（.spec/issues/176-progress-server.md §3-2）。
"""

from progress_cmd import run


def read_branches(runner=run):
    """ローカルとリモートのブランチ名（remote 名を外し、重複を除き、*/HEAD を除く）。"""
    out = runner(["git", "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes"])
    names = set()
    for ref in out.splitlines():
        if ref.startswith("refs/heads/"):
            names.add(ref[len("refs/heads/"):])
        elif ref.startswith("refs/remotes/"):
            rest = ref[len("refs/remotes/"):].split("/", 1)
            if len(rest) == 2 and rest[1] != "HEAD":
                names.add(rest[1])
    return sorted(names)


def read_worktrees(runner=run):
    """worktree の list。各要素は {path, branch, prunable}（branch は refs/heads/ を外した名前か None）。"""
    out = runner(["git", "worktree", "list", "--porcelain"])
    return parse_worktrees(out)


def parse_worktrees(text):
    """`git worktree list --porcelain` を読む（-z は git 2.36 以降なので使わない）。"""
    result, cur = [], None
    for line in text.splitlines() + [""]:
        if not line:
            if cur:
                result.append(cur)
            cur = None
            continue
        key, _, value = line.partition(" ")
        if key == "worktree":
            cur = {"path": value, "branch": None, "prunable": False}
        elif cur is None:
            continue
        elif key == "branch":
            cur["branch"] = value.removeprefix("refs/heads/")
        elif key == "prunable":
            cur["prunable"] = True
    return result
