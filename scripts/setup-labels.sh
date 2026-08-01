#!/usr/bin/env bash
# ============================================================
# GitHub ラベルのプロビジョニング
# [Template] research-project-template 由来
# ============================================================
#
# ラベル定義の単一情報源。`.claude/rules/template/labels.md` の表とこのスクリプトが食い違わないよう、
# ラベルを増減する場合は必ず両方を更新すること。
#
# Usage:
#   bash scripts/setup-labels.sh          # 不足しているラベルを作成
#   bash scripts/setup-labels.sh --prune  # 定義に無いラベルを一覧表示（削除はしない）
#   bash scripts/setup-labels.sh --help   # この使い方を表示
#
# 冪等。既存ラベルは色・説明を更新する。
#
# Exit codes:
#   0 作成・更新した（または --prune / --help）
#   2 スキップ（gh 不在・未認証・GitHub リポジトリでない。要ユーザー対応）
#   1 引数エラー

set -uo pipefail

# ★ 引数の検証は gh の確認より前に行う。
#   さもないと `--help` が gh 未認証環境で「スキップ」になって使い方を出せない
case "${1:-}" in
  -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --prune|"") ;;
  *) echo "[labels] 不明な引数: $1（--prune / --help のみ）" >&2; exit 1 ;;
esac

# ラベルを作れないまま先に進むと /issue-create が前提チェックで停止する。
# インストール直後は gh 未認証・remote 未設定が正常にありうるので処理は止めないが、
# **後で何をすればよいかを必ず案内する**（黙ってスキップしない）
#
# 終了コード: 0=作成した / 2=スキップ（要ユーザー対応）/ 1=エラー
# 呼び出し側（worktree-init/init.sh, install.sh）は 2 を致命的として扱わない
skip_with_guidance() {
  echo "[labels] $1"
  echo "[labels] GitHub リポジトリを用意したあと、次を実行してください:"
  echo "[labels]   bash scripts/setup-labels.sh"
  echo "[labels] ラベルが無いと /issue-create が前提チェックで停止します。"
  exit 2
}

command -v gh >/dev/null 2>&1 || skip_with_guidance "gh が見つからないためスキップ"
gh repo view >/dev/null 2>&1 || skip_with_guidance "GitHub リポジトリではない（または未認証）ためスキップ"

# name|color|description
LABELS=(
  # --- 階層ラベル（種別の判別に使う。親子関係は GitHub ネイティブ sub-issue で表す） ---
  "epic|3E4B9E|ゴール。task をまとめる。worktree は持たない"
  "task|5A6FD8|1つのまとまった仕事。既定構成の issue を持つ。worktree は持たない"

  # --- 種類ラベル（issue 層。必須、1つ選ぶ） ---
  "survey|5319E7|文献・ライブラリ調査 → docs/surveys/"
  "spec|8A5CF6|仕様の作成・レビュー → .spec/issues/"
  "feature|0E8A16|新機能・実装"
  "validation|006B75|実装は仕様どおり動くか（実装の正しさ）"
  "experiment|FBCA04|仮説は正しいか（設計の正しさ）→ data/shared/experiments/"
  "bug|d73a4a|バグ修正"
  "docs|0075CA|ドキュメント"
  "refactor|D4C5F9|挙動を変えないコード改善"
  "chore|C5DEF5|CI・依存更新など"

  # --- 状態ラベル ---
  "blocked|B60205|他Issueや外部要因で待ち"

  # --- 自動処理の制御ラベル ---
  "out-of-date|795548|古くなったIssue。自動処理でスキップ"
  "user-action|E99695|ユーザー対応が必要。自動処理でスキップ"

  # --- 報告ラベル（定期レビュー等の報告 issue。作業種別ではない） ---
  "review-integrity|1D76DB|定期レビューの報告。/review-integrity が起票する"

  # --- 終了ラベル ---
  "wontfix|ffffff|やらないことにした"
  "duplicate|cfd3d7|重複"
)

if [ "${1:-}" = "--prune" ]; then
  echo "[labels] 定義に無いラベル（手動で確認して削除すること）:"
  DEFINED=$(printf '%s\n' "${LABELS[@]}" | cut -d'|' -f1 | sort)
  gh label list --limit 100 --json name -q '.[].name' | sort | comm -23 - <(echo "$DEFINED")
  exit 0
fi

CREATED=0
UPDATED=0
for entry in "${LABELS[@]}"; do
  IFS='|' read -r name color desc <<< "$entry"
  if gh label create "$name" --color "$color" --description "$desc" >/dev/null 2>&1; then
    echo "[labels] + $name"
    CREATED=$((CREATED+1))
  elif gh label edit "$name" --color "$color" --description "$desc" >/dev/null 2>&1; then
    UPDATED=$((UPDATED+1))
  else
    echo "[labels] ! $name の作成/更新に失敗"
  fi
done

echo "[labels] 作成 ${CREATED} 件 / 更新 ${UPDATED} 件"

# in-progress は意図的に定義しない。
# 「作業中」はブランチの有無で判定する（同じ状態を2通りに表現しないため）。
# 詳細は `.claude/rules/template/labels.md`「ラベル運用ルール」を参照。
if gh label list --limit 100 --json name -q '.[].name' | grep -qx "in-progress"; then
  echo "[labels] 注意: in-progress ラベルが存在します。"
  echo "[labels]   本テンプレートは作業中の判定をブランチの有無で行うため、このラベルは使いません。"
  echo "[labels]   既存Issueから外したうえで削除を検討してください。"
fi

exit 0
