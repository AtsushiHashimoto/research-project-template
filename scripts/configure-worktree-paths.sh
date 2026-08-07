#!/usr/bin/env bash
# ============================================================
# worktree の .git 参照を相対パスにする設定
# [Template] research-project-template 由来
# ============================================================
#
# 背景:
#   git worktree add は既定で .git 参照を「絶対パス」で 2 箇所に書き込む。
#     worktrees/issueN/.git        → gitdir: <絶対パス>/.git/worktrees/issueN
#     .git/worktrees/issueN/gitdir → <絶対パス>/worktrees/issueN/.git
#
#   devcontainer はリポジトリを /workspace にマウントするため、ホストとコンテナで
#   絶対パスが一致しない。結果として **worktree を作成した側の環境でしか git / gh が
#   動かない**（双方向に壊れる）。
#
#   worktree.useRelativePaths=true にすると相対パスで書かれ、両環境から解決できる。
#
# 要件:
#   **両方の環境**の git が 2.48 以降であること
#   （worktree.useRelativePaths / --relative-paths の対応バージョン）
#
#   ★ 「両方」が要件である理由:
#     .git/config はホストと devcontainer で同一実体（bind mount）。片側だけ 2.48 以降に
#     なった状態でこのスクリプトが useRelativePaths を書くと、最初の相対 worktree 作成時に
#     git は **extensions.relativeWorktrees=true と core.repositoryformatversion=1** を
#     書き込む。以降、古い側の git は当該リポジトリの **全コマンド** が
#       fatal: unknown repository extension found: relativeworktrees
#     で落ちる（git 2.34.1 で実測）。しかも extensions を消す git config 自体も落ちるため、
#     .git/config を手で編集しないと復旧できない＝実質的に片道切符。
#     バージョン判定は「自分の git」しか見られないため、明示的な opt-in を必須にする。
#
#     （関連: 記録を手で相対パスに書き換えた場合は拡張が書かれないため fatal にならない
#      代わりに、古い git が worktree を prunable と誤判定し、git gc --auto 経由の
#      git worktree prune が登録ごと削除する。派生プロジェクト delta-clip-dev #167 で実測。
#      どちらの経路も「片側だけ新しい」状態が原因なので、対策は opt-in で共通。）
#
# 呼び出し元:
#   - .devcontainer/post-create.sh              （コンテナ側）
#   - .claude/skills/worktree-init/init.sh      （ホスト側 /worktree-init 経由）

set -uo pipefail

# 外部コマンドの出力を捨てずに前置きして流すためのヘルパ。
# 例: git worktree repair は「一部しか直せなかった」ときも exit 0 で stderr に
# 警告を出すため、握りつぶすと最も知りたい情報だけが消える。
log_indented() {
  while IFS= read -r line; do
    [ -n "$line" ] && echo "[worktree-paths]   $line"
  done
}

# ---------------------------------------------------------------------------
# git リポジトリの確認
#
# ★ stderr を捨てないこと。他環境が相対パス worktree を有効化したあと、
#   git < 2.48 は relativeWorktrees 拡張を理解できず **全コマンドが fatal** になる。
#   ここで握り潰すと「git リポジトリではない」と誤報し、本当の原因が見えなくなる。
# ---------------------------------------------------------------------------
if ! rev_parse_err=$(git rev-parse --show-toplevel 2>&1 >/dev/null); then
  case "$rev_parse_err" in
    *relativeworktrees* | *"unknown repository extension"*)
      echo "[worktree-paths] ERROR: この環境の git ($(git --version)) は relativeWorktrees 拡張に未対応です。" >&2
      echo "[worktree-paths]        他環境が相対パス worktree を有効化しているため、この環境から git は使えません。" >&2
      echo "[worktree-paths]        復旧手順は .claude/rules/template/git-workflow.md を参照してください。" >&2
      printf '%s\n' "$rev_parse_err" | log_indented >&2
      exit 0
      ;;
  esac
  echo "[worktree-paths] git リポジトリではないためスキップ"
  exit 0
fi

GIT_VERSION=$(git --version | awk '{print $3}')
GIT_MAJOR=${GIT_VERSION%%.*}
GIT_REST=${GIT_VERSION#*.}
GIT_MINOR=${GIT_REST%%.*}

if [ "$GIT_MAJOR" -gt 2 ] || { [ "$GIT_MAJOR" -eq 2 ] && [ "$GIT_MINOR" -ge 48 ]; }; then
  GIT_SUPPORTS_RELATIVE=true
else
  GIT_SUPPORTS_RELATIVE=false
fi

# ★ --bool で読むこと。git は 1 / yes / on も真として扱うので、文字列比較だと
#   git 自身が「有効」と見なしている設定を取りこぼす。
read_bool() {
  local v
  v=$(git config --bool --get "$1" 2>/dev/null) || v=""
  [ -n "$v" ] || v=false
  printf '%s' "$v"
}

# 両環境の更新を確認したら opt-in する:
#   git config worktree.relativePathsOptIn true
OPT_IN=$(read_bool worktree.relativePathsOptIn)
CURRENT_REL=$(read_bool worktree.useRelativePaths)

RELATIVE_PATHS=false

if [ "$GIT_SUPPORTS_RELATIVE" = "true" ]; then
  if [ "$CURRENT_REL" = "true" ]; then
    # ★ 既に有効なリポジトリは **そのまま尊重する**。
    #   本スクリプトの旧版は opt-in 無しで useRelativePaths を書いていたため、
    #   この状態のリポジトリが既に存在する。ここで unset すると、両環境とも
    #   2.48 以降の健全なプロジェクトを絶対パスに退行させてしまう。
    #   ただし opt-in が無い場合は「未確認のまま有効」なので必ず警告する。
    RELATIVE_PATHS=true
    if [ "$OPT_IN" = "true" ]; then
      echo "[worktree-paths] git ${GIT_VERSION}: 相対パス worktree は有効です"
    else
      echo "[worktree-paths] WARNING: worktree.useRelativePaths が opt-in 無しで有効になっています（旧版の設定）。" >&2
      echo "[worktree-paths]          両環境が git 2.48 以降であることを確認し、次を実行してください:" >&2
      echo "[worktree-paths]            git config worktree.relativePathsOptIn true" >&2
      echo "[worktree-paths]          満たさない場合の無効化には .git/config の手編集が要ります" >&2
      echo "[worktree-paths]          （手順は .claude/rules/template/git-workflow.md）。" >&2
    fi
  elif [ "$OPT_IN" = "true" ]; then
    # 設定の書き込みが成功したときだけ有効とみなす（読み取り専用や lock 競合への備え）
    if git config worktree.useRelativePaths true; then
      RELATIVE_PATHS=true
      echo "[worktree-paths] git ${GIT_VERSION}: 相対パス worktree を有効化しました"
    else
      echo "[worktree-paths] ERROR: worktree.useRelativePaths の設定に失敗しました" >&2
    fi
  else
    echo "[worktree-paths] git ${GIT_VERSION}: 相対パスに対応していますが opt-in が未設定のため使いません"
    echo "[worktree-paths] → 他環境（ホスト / devcontainer）も 2.48 以降であることを確認してから:"
    echo "[worktree-paths]     git config worktree.relativePathsOptIn true"
  fi
elif [ "$CURRENT_REL" = "true" ]; then
  # ★ 危険な混在状態: 自分は未対応なのに設定が有効 = 他環境が相対パス化した後。
  #   まだ相対 worktree が 1 つも作られていなければ拡張は書かれておらず、
  #   コマンドは通る。この隙にしか警告できない。
  echo "[worktree-paths] ERROR: 他環境が worktree を相対パス化していますが、この環境の git は ${GIT_VERSION} です。" >&2
  echo "[worktree-paths]        この環境で git gc / git worktree prune を実行しないでください（登録が消えます）。" >&2
  echo "[worktree-paths]        恒久対策は両環境の git を 2.48 以降にするか、.git/config から" >&2
  echo "[worktree-paths]        worktree.useRelativePaths を外すことです（git-workflow.md 参照）。" >&2
else
  echo "[worktree-paths] git ${GIT_VERSION}: 相対パス worktree は未対応のため使いません（2.48 以降で opt-in 可）"
  echo "[worktree-paths] → worktree に対する git コマンドは、いずれか 1 つの環境からのみ実行してください"
  echo "[worktree-paths]   （ファイル編集はどの環境からでも可）"
fi

# ---------------------------------------------------------------------------
# 既存 worktree の参照を修復する。
#
# ★ 相対パス化が有効なときだけ実行する。
#
#   相対パス化が無効なときの 'git worktree repair' は「実行した環境から見た絶対パス」で
#   参照を上書きする。本スクリプトは post-create.sh（コンテナ側）と
#   .claude/skills/worktree-init/init.sh（ホスト側）の両方から呼ばれるため、
#   無条件に実行すると双方が互いの参照を壊し合い、後から実行した側でしか
#   git / gh が動かなくなる。実際に派生プロジェクト（delta-clip-dev #167）で
#   全 11 worktree がホストから prunable になり、うち 3 件は登録ごと消えていた。
#
#   単一環境で使う場合の 'git worktree repair' は正しい復旧手段。
#   その場合は「正」と決めた環境から手で実行すること（git-workflow.md 参照）。
# ---------------------------------------------------------------------------
if [ -d "$(git rev-parse --git-common-dir)/worktrees" ] && [ "$RELATIVE_PATHS" = "true" ]; then
  if repair_out=$(git worktree repair 2>&1); then
    echo "[worktree-paths] 既存 worktree の参照を修復しました"
    printf '%s\n' "$repair_out" | log_indented
  else
    echo "[worktree-paths] ERROR: git worktree repair に失敗しました" >&2
    printf '%s\n' "$repair_out" | log_indented >&2
  fi
fi

exit 0
