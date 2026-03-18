# セキュリティ分析: DevContainer 自動化機能

このドキュメントでは、本テンプレートの自動化機能についてセキュリティ観点からのリスク評価を行います。

## 対象読者

- このテンプレートを使用する開発者・研究者
- チームへの導入を検討している管理者

## リスク評価サマリー

| 仕組み | リスク | 緩和策 |
|--------|--------|--------|
| `--dangerously-skip-permissions` | **高** | コンテナ隔離 |
| Docker-outside-of-Docker | **中〜高** | 使用しない場合は無効化可能 |
| `.gitconfig` / `.config/gh` マウント | **中** | 読み取り専用化可能 |
| Named Volume 認証永続化 | **低〜中** | プロジェクト別分離 |
| Deterministic machine-id | **低** | 利便性とのトレードオフ |
| `settings.local.json` 許可リスト | **低** | スコープ限定済み |
| `sudo NOPASSWD` | **低** | 開発コンテナ標準 |

## 詳細分析

### 1. `--dangerously-skip-permissions` (高リスク)

**何をしているか**: Claude Code の全てのツール実行（ファイル読み書き、コマンド実行、Web アクセス等）をユーザー確認なしで自動実行します。Dockerfile の alias と claude-san スクリプトの両方で適用されます。

**リスク**:
- Claude Code が生成・実行するコマンドに対する人間のレビューがない
- 悪意あるコードや意図しないコマンドが確認なしで実行される可能性
- ファイルシステムの任意の場所への読み書きが可能

**緩和要因**:
- 実行環境がコンテナ内に限定されている
- Claude Code 自体にセーフティ機構がある（destructive operation の回避等）
- `settings.local.json` で一部のコマンドのみ明示的に許可している（ただし alias が全体を上書き）

**対策案（より安全にしたい場合）**:
- alias を削除し、`settings.local.json` の許可リストのみで運用
- `claude-san` から `--dangerously-skip-permissions` を除去
- 重要な操作は対話モードで確認

### 2. Docker-outside-of-Docker (中〜高リスク)

**何をしているか**: コンテナ内からホストの Docker デーモンにアクセスできるようにしています（`ghcr.io/devcontainers/features/docker-outside-of-docker`）。

**リスク**:
- コンテナ内のプロセスがホスト上の任意のコンテナを操作可能
- 特権コンテナの起動によるホストファイルシステムへのアクセス（コンテナエスケープ）
- `--dangerously-skip-permissions` と組み合わせると、Claude Code がホスト環境を操作する経路になりうる

**緩和要因**:
- 研究用途では Docker を使わないケースも多い（その場合リスクは発生しない）

**対策案**:
- Docker が不要な場合は `features` セクションから削除:
  ```jsonc
  // "features": {
  //   "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
  // }
  ```

### 3. ホスト認証情報のマウント (中リスク)

**何をしているか**: ホストの `.gitconfig` と `.config/gh`（GitHub CLI 認証）をコンテナにバインドマウントしています。

**リスク**:
- コンテナ内のプロセスがホストの GitHub 認証トークンを読み取り可能
- `--dangerously-skip-permissions` と組み合わせると、Claude Code が認証情報を使って任意の GitHub 操作（他リポジトリへのアクセス、Issue/PR 操作等）を実行可能
- トークンのスコープ次第では、組織全体のリポジトリにアクセスできる可能性

**緩和要因**:
- `gh` の認証トークンは通常、ユーザー自身の権限範囲に限定
- Git 操作は通常のワークフローで必要

**対策案**:
- GitHub CLI のトークンスコープを最小限に設定
- 読み取り専用マウントに変更:
  ```jsonc
  "source=${localEnv:HOME}/.config/gh,target=/home/vscode/.config/gh,type=bind,readonly"
  ```

### 4. Named Volume による認証永続化 (低〜中リスク)

**何をしているか**: Claude Code の認証トークンをプロジェクト専用の Docker Named Volume (`claude-code-config-${localWorkspaceFolderBasename}`) に保存しています。

**リスク**:
- Volume 名はプロジェクト名から推測可能
- ホスト上の他のコンテナから `docker run -v claude-code-config-xxx:/data` で Volume の中身を読み取り可能
- Volume にはClaude の認証トークンが含まれる

**緩和要因**:
- 他のコンテナからのアクセスには Docker コマンドの実行権限が必要
- 個人開発環境では実質的なリスクは低い
- プロジェクト別に分離されている（他プロジェクトの認証にはアクセスできない）

**対策案**:
- 共有マシンでは使用後に Volume を削除: `docker volume rm claude-code-config-xxx`

### 5. Deterministic machine-id (低リスク)

**何をしているか**: ワークスペース名から MD5 ハッシュで `/etc/machine-id` を生成しています。これにより、コンテナ再ビルド後も同じ machine-id が再現され、Claude Code が再認証を要求しません。

**リスク**:
- machine-id がワークスペース名から予測可能
- 同じワークスペース名を持つコンテナは同じ machine-id を持つ

**緩和要因**:
- machine-id 単体では認証トークンにアクセスできない（Volume も必要）
- 攻撃に利用するには Volume へのアクセスが別途必要
- 利便性（再認証不要）とのトレードオフとして妥当

### 6. `settings.local.json` の許可リスト (低リスク)

**何をしているか**: 以下のコマンドを Claude Code が確認なしで実行できるよう許可しています:

```json
{
  "permissions": {
    "allow": [
      "Bash(gh issue:*)",
      "Bash(grep:*)",
      "Bash(gh api:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git config:*)",
      "Bash(git push:*)",
      "WebFetch(domain:docs.anthropic.com)"
    ]
  }
}
```

**リスク**:
- `git push:*` により、意図しないブランチへのプッシュが可能
- `gh issue:*` / `gh api:*` により、Issue の作成・変更が確認なしで実行される

**緩和要因**:
- スコープが Git/GitHub 操作に限定されている
- ファイルシステム操作やネットワークアクセスは含まれていない
- Issue 駆動ワークフローで必要な最小限の権限

**注意**: `--dangerously-skip-permissions` alias が有効な場合、この設定は実質的に無意味です（全てが許可されるため）。alias を無効化した場合にのみ、この許可リストが効力を持ちます。

### 7. `sudo NOPASSWD` (低リスク)

**何をしているか**: vscode ユーザーがパスワードなしで root 権限を取得できます。

**リスク**:
- コンテナ内で root として任意の操作が可能

**緩和要因**:
- DevContainer の標準的な設定
- コンテナ外のホスト環境には影響しない（Docker-outside-of-Docker を除く）
- 開発環境では一般的に許容される

## 総合評価

### 個人研究用途: 妥当

個人の開発マシン上で、自分のプロジェクトに対して使用する場合、**リスクは許容範囲内**です。

- コンテナ隔離により、ホスト環境への直接的な影響は限定的
- 認証情報はユーザー自身のもの
- 利便性（再認証不要、確認スキップによる高速開発）のメリットが大きい

### チーム・共有環境での使用: 追加対策が必要

| 対策 | 重要度 |
|------|--------|
| `--dangerously-skip-permissions` alias の削除 | **必須** |
| Docker-outside-of-Docker の無効化 | **推奨** |
| GitHub トークンの最小スコープ化 | **推奨** |
| 使用後の Volume 削除の運用ルール化 | 任意 |
| `.gitconfig` / `.config/gh` の読み取り専用化 | 任意 |

### CI/CD 環境での使用: 非推奨

`--dangerously-skip-permissions` を CI/CD パイプラインで使用することは推奨しません。CI では Claude Code の対話モードを使用するか、専用の API ベースのワークフローを構築してください。

## 設定変更の手順

### alias を無効化する場合

`.devcontainer/Dockerfile` から以下の行を削除:

```dockerfile
RUN echo 'alias claude="claude --dangerously-skip-permissions"' >> /etc/bash.bashrc
```

`claude-san` からも `--dangerously-skip-permissions` を除去:

```bash
# claude-san 内の CLAUDE_CMD を変更
CLAUDE_CMD="claude $CLAUDE_ARGS"
```

### Docker-outside-of-Docker を無効化する場合

`.devcontainer/devcontainer.json` の `features` セクションを削除:

```jsonc
// 削除またはコメントアウト
// "features": {
//   "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
// }
```
