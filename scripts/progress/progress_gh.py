"""GitHub から issue と PR を全件取る（gh api graphql）。close の前の確認も読む（書き込みはしない）。

全ページが成功し、番号で重複を除いた件数が totalCount と一致したときだけ結果を返す。
一部だけの木を出さないため、それ以外は FetchError にする（.spec/issues/176-progress-server.md §3）。
issue の本文（body）は取らない（.spec/issues/201-progress-cards.md §5-1 K2）。PR の本文は open の PR だけ取る（同 §3-1 案 B）。
"""

import json

from progress_cmd import FetchError, failure, run, run_raw

QUERY = """
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $endCursor, states: [OPEN, CLOSED]) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes {
        number title state stateReason url updatedAt createdAt
        labels(first: 20) { totalCount nodes { name } }
        parent { number repository { nameWithOwner } }
        closedByPullRequestsReferences(first: 10, includeClosedPrs: true) {
          totalCount nodes { number state url }
        }
      }
    }
  }
}
"""

PULL_QUERY = """
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: 100, after: $endCursor) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes { number state url headRefName headRefOid isCrossRepository }
    }
  }
}
"""

# 201 §3-1 案 B: 本文の Refs #N を読むのは open の PR だけ（全件の本文は取らない）
OPEN_BODY_QUERY = """
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: 100, after: $endCursor, states: [OPEN]) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes { number body }
    }
  }
}
"""

STATE_QUERY = """
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      state labels(first: 100) { totalCount nodes { name } } subIssues { totalCount }
    }
  }
}
"""


def current_repo(runner=run):
    """cwd の repo（OWNER/NAME）。"""
    repo = runner(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).strip()
    if "/" not in repo:
        raise FetchError(f"cwd の repo 名を読めない（gh repo view の出力: {repo!r}）")
    return repo


def paged(repo, query, field, runner):
    owner, name = repo.split("/", 1)
    out = runner(["gh", "api", "graphql", "--paginate", "--slurp",
                  "-f", f"query={query}", "-f", f"owner={owner}", "-f", f"name={name}"])
    try:
        pages = json.loads(out)
    except json.JSONDecodeError as e:
        raise FetchError(f"gh の出力を JSON として読めない: {e}") from e
    return collect(pages, field)


def fetch_issues(repo, runner=run):
    """repo の全 issue を返す。戻り値は GraphQL の node の list（番号順）。"""
    return paged(repo, QUERY, "issues", runner)


def fetch_pulls(repo, runner=run):
    """repo の全 PR（open・merged・closed）を返す。open の PR には本文 `body` を足す（201 §3-1 案 B）。"""
    pulls = paged(repo, PULL_QUERY, "pullRequests", runner)
    bodies = {p["number"]: p["body"] or "" for p in paged(repo, OPEN_BODY_QUERY, "pullRequests", runner)}
    for p in pulls:
        if p["state"] == "OPEN" and p["number"] in bodies:
            p["body"] = bodies[p["number"]]
    return pulls


def graphql_error(errors):
    """GraphQL の errors（空でない list。呼び出し側で list にそろえる）を、先頭の message を添えた FetchError にする。"""
    first = errors[0]
    return FetchError(f"GraphQL のエラー: {first.get('message', first) if isinstance(first, dict) else first}")


def collect(pages, field="issues"):
    """--slurp の出力（ページの list）を検査して node の list にする。"""
    if not isinstance(pages, list) or not pages or not all(isinstance(p, dict) for p in pages):
        raise FetchError("gh の出力がページの list になっていない")
    by_number = {}
    total = None
    for page in pages:
        if page.get("errors"):
            raise graphql_error(page["errors"])
        repo = (page.get("data") or {}).get("repository")
        if repo is None:
            raise FetchError("repository が取れない（名前か権限を確認）")
        conn = repo[field]
        total = conn["totalCount"]
        for node in conn["nodes"]:
            by_number[node["number"]] = node
    if len(by_number) != total:
        raise FetchError(f"件数が合わない（取れた {len(by_number)} 件 / totalCount {total} 件）")
    return [by_number[n] for n in sorted(by_number)]


def fetch_issue_state(repo, number, runner=run_raw):
    """close の前に GitHub で取り直す（キャッシュを使わない。201 §6 順 6）。
    戻り値は {state, labels, subIssues}、issue が無い（PR の番号を含む）なら None、他の失敗は FetchError。
    gh は NOT_FOUND でも exit 1 で JSON を stdout に出すので、終了コードより先に stdout を読む。"""
    owner, name = repo.split("/", 1)
    argv = ["gh", "api", "graphql", "-F", f"number={number}",
            "-f", f"query={STATE_QUERY}", "-f", f"owner={owner}", "-f", f"name={name}"]
    code, out, err = runner(argv)
    try:
        body = json.loads(out)
    except json.JSONDecodeError:
        raise failure(argv, code, err) from None
    if not isinstance(body, dict):
        raise failure(argv, code, err) if code != 0 else shape_error(body)
    errors = body.get("errors") or []
    errors = errors if isinstance(errors, list) else [errors]
    if any(isinstance(e, dict) and e.get("type") == "NOT_FOUND" for e in errors):
        return None
    if errors:                                # exit 0 でも errors を返すことがある（終了コードでは言えない）
        raise graphql_error(errors)
    if code != 0:
        raise failure(argv, code, err)
    try:
        repo_node = (body.get("data") or {}).get("repository")
        if repo_node is None:
            raise FetchError("repository が取れない（名前か権限を確認）")
        it = repo_node.get("issue")
        if it is None:
            return None
        return {"state": it["state"], "labels": [x["name"] for x in it["labels"]["nodes"]],
                "subIssues": it["subIssues"]["totalCount"]}
    except (KeyError, TypeError, AttributeError) as e:   # 形が違えば FetchError（perform が 502 にする）
        raise shape_error(e) from e


def shape_error(what):
    return FetchError(f"gh の応答の形が想定と違う: {what!r}")
