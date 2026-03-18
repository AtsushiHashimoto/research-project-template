# claude-san — Rate Limit 自動再開付き Claude Code ランチャー

`claude-san` は Claude Code を tmux + [autoclaude](https://github.com/henryaj/autoclaude) で起動するラッパースクリプトです。Rate limit に達した際に自動的にセッションを再開します。

## 仕組み

```
┌─ tmux session ──────────────────────────────────┐
│ ┌─ pane 0 (maximized) ─┐  ┌─ pane 1 ─────────┐ │
│ │                       │  │                   │ │
│ │  claude               │  │  autoclaude       │ │
│ │  --dangerously-skip-  │  │  (rate limit     │ │
│ │    permissions        │  │   監視 & 自動    │ │
│ │                       │  │   再開)          │ │
│ └───────────────────────┘  └───────────────────┘ │
└──────────────────────────────────────────────────┘
```

1. **tmux セッション**を作成（タイムスタンプで一意な名前）
2. **左ペイン**: Claude Code を `--dangerously-skip-permissions` 付きで起動
3. **右ペイン**: `autoclaude` が Claude の出力を監視し、rate limit 検出時に自動再開
4. Claude ペインを最大化して表示

## 使い方

### 基本コマンド

```bash
# 新規セッションで対話モード
claude-san

# 前回の会話を継続
claude-san -c
claude-san --continue

# 特定のセッションを再開
claude-san -r <session-id>
```

### tmux セッション管理

```bash
# セッション一覧を表示
tmux ls

# 既存セッションに接続（デタッチ後の再接続）
tmux attach -t <session-name>

# セッションをデタッチ（バックグラウンドに移行）
# tmux内で Ctrl+B → D
```

### tmux ペイン操作

```bash
# ペイン間を移動
# Ctrl+B → 矢印キー

# 最大化されたペインを解除して autoclaude ペインを確認
# Ctrl+B → Z

# 再度最大化
# Ctrl+B → Z
```

## autoclaude とは

[autoclaude](https://github.com/henryaj/autoclaude) は Claude Code の出力を監視し、rate limit エラーを検出すると自動的にセッションを再開するツールです。

- Claude Code の terminal 出力をリアルタイム監視
- Rate limit メッセージを検出
- 待機時間経過後に自動で Enter を送信して再開

## インストール

DevContainer を使用している場合、`claude-san` と `autoclaude` は Dockerfile で自動インストールされます。手動セットアップは不要です。

`claude-san` スクリプトは `postCreateCommand` で `/usr/local/bin/claude-san` にシンボリックリンクされます。

## 通常の `claude` との違い

| | `claude` | `claude-san` |
|---|---------|-------------|
| tmux | なし | あり |
| rate limit 自動再開 | なし | あり（autoclaude） |
| セッション永続化 | ターミナル閉じで終了 | tmux でバックグラウンド継続 |
| 権限確認 | alias で skip | skip |

> **Note**: Dockerfile の alias 設定により、`claude` も `--dangerously-skip-permissions` 付きで起動します。権限確認の動作は同じです。
