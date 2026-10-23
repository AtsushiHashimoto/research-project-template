"""GitHub から issue を全件取る（gh api graphql）。

全ページが成功し、番号で重複を除いた件数が totalCount と一致したときだけ結果を返す。
一部だけの木を出さないため、それ以外は FetchError にする（.spec/issues/176-progress-server.md §3）。
"""

import json

from progress_cmd import FetchError, run

QUERY = """
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $endCursor, states: [OPEN, CLOSED]) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes {
        number title state stateReason url updatedAt
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


def current_repo(runner=run):
    """cwd の repo（OWNER/NAME）。"""
    repo = runner(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).strip()
    if "/" not in repo:
        raise FetchError(f"cwd の repo 名を読めない（gh repo view の出力: {repo!r}）")
    return repo


def fetch_issues(repo, runner=run):
    """repo の全 issue を返す。戻り値は GraphQL の node の list（番号順）。"""
    owner, name = repo.split("/", 1)
    out = runner(["gh", "api", "graphql", "--paginate", "--slurp",
                  "-f", f"query={QUERY}", "-f", f"owner={owner}", "-f", f"name={name}"])
    try:
        pages = json.loads(out)
    except json.JSONDecodeError as e:
        raise FetchError(f"gh の出力を JSON として読めない: {e}") from e
    return collect(pages)


def collect(pages):
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
        issues = repo["issues"]
        total = issues["totalCount"]
        for node in issues["nodes"]:
            by_number[node["number"]] = node
    if len(by_number) != total:
        raise FetchError(f"件数が合わない（取れた {len(by_number)} 件 / totalCount {total} 件）")
    return [by_number[n] for n in sorted(by_number)]
