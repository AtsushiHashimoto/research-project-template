#!/usr/bin/env bash
# ============================================================
# /spec-init 用の証拠収集
# [Template] research-project-template 由来
# ============================================================
#
# .spec/ の必読ファイルを埋めるための「候補の材料」を既存資産から集める。
# 判断はしない。集めて並べるだけ。採否は対話で決める。
#
# Usage: bash .claude/skills/spec-init/gather-evidence.sh

set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT" || exit 1

section() { printf '\n########## %s ##########\n' "$1"; }

# ---------------------------------------------------------------------------
section "1. .spec/ の記入状況"
# ---------------------------------------------------------------------------
for f in core-rules invariants known-issues; do
  p=".spec/${f}.md"
  if [ ! -f "$p" ]; then
    echo "$p: ❌ 未作成 → テンプレートから復元が必要（auto-reviewer は停止する）"
    continue
  fi
  # 既定は R-D01 / INV-D01 / KI-D01 形式。「# 既定の」見出し以降のみを数える
  # （書き方の説明やコメントアウトされた記入例を拾わないため）
  n_def=$(awk '/^# 既定の/{s=1} /^# プロジェクト固有/{s=0} s && /^### (R|INV|KI)-D[0-9]+:/{c++} END{print c+0}' "$p")
  # 固有は「# プロジェクト固有」見出し以降のみを数える
  n_own=$(awk '/^# プロジェクト固有/{s=1} s && /^### (R|INV|KI)-[0-9]+:/{c++} END{print c+0}' "$p")
  if [ "${n_def:-0}" -eq 0 ]; then
    echo "$p: ❌ 既定が削除されている（既定 0 / 固有 ${n_own:-0}）→ auto-reviewer は停止する"
  elif [ "${n_own:-0}" -eq 0 ]; then
    echo "$p: ⚠️  既定のみ（既定 ${n_def} / 固有 0）→ 動作するが本スキルで固有項目の追加を推奨"
  else
    echo "$p: ✅ 既定 ${n_def} / 固有 ${n_own}"
  fi
done

# ---------------------------------------------------------------------------
section "2. known-issues.md の候補: closed した bug ラベル Issue"
# ---------------------------------------------------------------------------
if command -v gh >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
  gh issue list --state closed --label bug --limit 40 \
    --json number,title,closedAt \
    -q '.[]|"#\(.number)\t\(.closedAt[0:10])\t\(.title)"' 2>/dev/null \
    || echo "(取得失敗 / bug ラベル無し)"
else
  echo "(gh 未認証またはリポジトリ外のためスキップ)"
fi

# ---------------------------------------------------------------------------
section "3. known-issues.md の候補: wontfix / 断念した Issue"
# ---------------------------------------------------------------------------
if command -v gh >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
  gh issue list --state closed --label wontfix --limit 25 \
    --json number,title -q '.[]|"#\(.number)\t\(.title)"' 2>/dev/null \
    || echo "(wontfix ラベル無し)"
else
  echo "(スキップ)"
fi

# ---------------------------------------------------------------------------
section "4. known-issues.md の候補: revert / 修正のやり直しコミット"
# ---------------------------------------------------------------------------
git log --oneline --grep='revert\|Revert\|やり直し\|差し戻' -i -30 2>/dev/null \
  | head -20 || echo "(該当なし)"

# ---------------------------------------------------------------------------
section "5. core-rules.md の候補: CLAUDE.md の禁止・必須表現"
# ---------------------------------------------------------------------------
if [ -f .claude/CLAUDE.md ]; then
  grep -nE '禁止|必ず|絶対|してはいけない|しない' .claude/CLAUDE.md \
    | grep -vE '^\s*[0-9]+:\s*\|' | head -25
else
  echo "(.claude/CLAUDE.md が無い)"
fi

# ---------------------------------------------------------------------------
section "6. invariants.md の候補: 設計判断を含む記録"
# ---------------------------------------------------------------------------
echo "--- docs/ の ADR / 設計文書 ---"
find docs .dev -maxdepth 2 -type f -name '*.md' 2>/dev/null \
  | grep -iE 'decision|adr|design|architecture' | head -10 || true
echo "--- 設計判断に言及する Issue（closed / feature・refactor）---"
if command -v gh >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
  gh issue list --state closed --limit 60 --json number,title,labels \
    -q '.[]|select(.labels[].name|test("feature|refactor"))|"#\(.number)\t\(.title)"' 2>/dev/null \
    | head -20 || echo "(取得失敗)"
else
  echo "(スキップ)"
fi

# ---------------------------------------------------------------------------
section "7. 参考: プロジェクトの規模"
# ---------------------------------------------------------------------------
if command -v gh >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
  echo -n "Issue 総数(closed): "; gh issue list --state closed --limit 500 --json number -q 'length' 2>/dev/null
fi
echo -n "コミット数: "; git rev-list --count HEAD 2>/dev/null

printf '\n########## 収集完了 ##########\n'
