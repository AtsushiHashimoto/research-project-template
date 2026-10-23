"""GitHub から issue を全件取る（gh api graphql）。

全ページが成功し、番号で重複を除いた件数が totalCount と一致したときだけ結果を返す。
一部だけの木を出さないため、それ以外は FetchError にする（.spec/issues/176-progress-server.md §3）。
"""

import json
import subprocess

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


class FetchError(Exception):
    """取得の失敗。メッセージは画面の帯とログにそのまま出す。"""


def run(argv):
    """コマンドを実行して stdout を返す。失敗は FetchError（終了コードと stderr の先頭を添える）。"""
    try:
        done = subprocess.run(argv, capture_output=True, text=True, timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FetchError(f"{argv[0]} を実行できない: {e}") from e
    if done.returncode != 0:
        head = done.stderr.strip().splitlines()[:3]
        raise FetchError(f"{' '.join(argv[:3])} が終了コード {done.returncode}: {' / '.join(head)}")
    return done.stdout


def current_repo(runner=run):
    """cwd の repo（OWNER/NAME）。"""
    return runner(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).strip()


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
    if not isinstance(pages, list) or not pages:
        raise FetchError("ページが 1 つも無い")
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
