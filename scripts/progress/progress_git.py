"""手元の git から ref・基準・worktree を読む（fetch はしない）。

GitHub の取得とは失敗の仕方が違うので別にしてある。ここが失敗しても木は出し、
「作業中」の列だけを不明にする（.spec/issues/176-progress-server.md §3-2、201 §3-2）。
"""

from progress_cmd import failure, run, run_raw

BASES = ("refs/remotes/origin/main", "refs/heads/main")   # 基準の ref（この順で最初にあるもの）


def read_refs(runner=run):
    """ローカルとリモートの ref。各要素は {refname, name（remote 名を外した名前）, oid, time（committer の unix 秒）}。
    */HEAD は除く。"""
    out = runner(["git", "for-each-ref", "--format=%(refname)%09%(objectname)%09%(committerdate:unix)",
                  "refs/heads", "refs/remotes"])
    refs = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        refname, oid, when = parts
        if refname.startswith("refs/heads/"):
            name = refname[len("refs/heads/"):]
        elif refname.startswith("refs/remotes/"):
            rest = refname[len("refs/remotes/"):].split("/", 1)
            if len(rest) != 2 or rest[1] == "HEAD":
                continue
            name = rest[1]
        else:
            continue
        refs.append({"refname": refname, "name": name, "oid": oid, "time": int(when or 0)})
    return refs


def read_base(runner=run_raw):
    """基準の ref の完全な名前。どれも無ければ None。rev-parse は「無い」を終了コード 1 で返すので、
    1 だけを「無い」と読み、それ以外の失敗は FetchError にする。"""
    for ref in BASES:
        argv = ["git", "rev-parse", "--verify", "-q", ref]
        code, _, err = runner(argv)
        if code == 0:
            return ref
        if code != 1:
            raise failure(argv, code, err)
    return None


def read_unmerged(base, runner=run):
    """基準に含まれない tip を持つ ref の完全な refname の集合。"""
    out = runner(["git", "for-each-ref", f"--no-merged={base}", "--format=%(refname)", "refs/heads", "refs/remotes"])
    return set(out.split())


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
