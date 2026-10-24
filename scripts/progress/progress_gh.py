"""GitHub から issue と PR を全件取る（gh api graphql）。close の前の確認も読む（書き込みはしない）。

全ページが成功し、番号で重複を除いた件数が totalCount と一致したときだけ結果を返す。
一部だけの木を出さないため、それ以外は FetchError にする（.spec/issues/176-progress-server.md §3）。
本文（body）は取らない（.spec/issues/201-progress-cards.md §5-1 K2）。
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
    """repo の全 PR（open・merged・closed）を返す。"""
    return paged(repo, PULL_QUERY, "pullRequests", runner)


def collect(pages, field="issues"):
    """--slurp の出力（ページの list）を検査して node の list にする。"""
    if not isinstance(pages, list) or not pages or not all(isinstance(p, dict) for p in pages):
        raise FetchError("gh の出力がページの list になっていない")
    by_number = {}
    total = None
    for page in pages:
        if page.get("errors"):
            raise FetchError(f"GraphQL のエラー: {page['errors'][0].get('message', page['errors'][0])}")
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
    errors = body.get("errors") or [] if isinstance(body, dict) else []
    if any(isinstance(e, dict) and e.get("type") == "NOT_FOUND" for e in errors):
        return None
    if errors or code != 0 or not isinstance(body, dict):
        raise failure(argv, code, err or str(errors[:1]))
    repo_node = (body.get("data") or {}).get("repository")
    if repo_node is None:
        raise FetchError("repository が取れない（名前か権限を確認）")
    it = repo_node.get("issue")
    if it is None:
        return None
    try:
        return {"state": it["state"], "labels": [x["name"] for x in it["labels"]["nodes"]],
                "subIssues": it["subIssues"]["totalCount"]}
    except (KeyError, TypeError) as e:
        raise FetchError(f"gh の応答の形が想定と違う: {e!r}") from e
