#!/usr/bin/env bash
# Regression tests for scripts/setup-worktree.sh -- data/shared linking (#194).
#
# The bug: data/shared/.gitkeep was tracked, so checkout always created data/shared as
# a real directory, and `ln -sf` then put the link INSIDE it (data/shared/shared).
# Data written to data/shared never reached the shared store and died with the worktree.
#
# Everything runs against a throwaway repository under $TMPDIR; the real store is
# never touched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup-worktree.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

# ------------------------------------------------------------------ fixture
# A miniature repo with a main checkout, a store, and one worktree.
setup_fixture() {
    FIX=$(mktemp -d)
    export FIX
    (
        cd "$FIX" || exit 1
        git init -q main
        cd main || exit 1
        git config user.email t@example.com
        git config user.name t
        mkdir -p .claude data/shared/datasets scripts
        cat > .claude/worktree-config.json <<'JSON'
{"version":"1.1","shared_data_path":"data/shared","path_type":"relative"}
JSON
        cp "$SETUP" scripts/setup-worktree.sh
        chmod +x scripts/setup-worktree.sh
        # data/shared is deliberately NOT tracked -- that is the fix under test.
        printf 'data/shared\nworktrees/\n' > .gitignore
        echo marker > data/shared/datasets/store-marker.txt
        git add -A >/dev/null
        git commit -qm init
        git worktree add -q worktrees/wt -b wt >/dev/null 2>&1
    )
    WT="$FIX/main/worktrees/wt"
    STORE="$FIX/main/data/shared"
}
teardown_fixture() { [[ -n "${FIX:-}" ]] && rm -rf "$FIX"; }

run_setup() { (cd "$WT" && bash scripts/setup-worktree.sh >/dev/null 2>&1); }

resolved() { readlink -f "$WT/data/shared" 2>/dev/null || echo ""; }
store_intact() { [[ -f "$STORE/datasets/store-marker.txt" ]] && echo yes || echo no; }

echo "=== setup-worktree.sh: data/shared linking (#194) ==="

# T1: the reported symptom -- a real directory holding only .gitkeep must become a link
setup_fixture
mkdir -p "$WT/data/shared" && touch "$WT/data/shared/.gitkeep"
run_setup
check "T1 real dir with .gitkeep -> link to store" "$(resolved)" "$(readlink -f "$STORE")"
check "T1 result is a symlink" "$([[ -L "$WT/data/shared" ]] && echo yes || echo no)" "yes"
teardown_fixture

# T2: the nested-link artefact left by the old script must be repaired
setup_fixture
mkdir -p "$WT/data/shared" && ln -s "$STORE" "$WT/data/shared/shared"
run_setup
check "T2 nested link repaired" "$(resolved)" "$(readlink -f "$STORE")"
teardown_fixture

# T3: idempotent -- running twice leaves a working link
setup_fixture
run_setup
run_setup
check "T3 idempotent" "$(resolved)" "$(readlink -f "$STORE")"
teardown_fixture

# T4: a link with the wrong depth (the ../../ mistake in D-07) is rebuilt, not kept
setup_fixture
rm -rf "$WT/data/shared"
mkdir -p "$WT/data" && ln -s ../../data/shared "$WT/data/shared"   # dangling
run_setup
check "T4 wrong-depth link rebuilt" "$(resolved)" "$(readlink -f "$STORE")"
teardown_fixture

# T5: real data in data/shared must stop the script, not be deleted
setup_fixture
mkdir -p "$WT/data/shared" && echo precious > "$WT/data/shared/precious.csv"
run_setup
check "T5 refuses (non-zero exit)" "$?" "1"
check "T5 data preserved" "$([[ -f "$WT/data/shared/precious.csv" ]] && echo yes || echo no)" "yes"
teardown_fixture

# T6: ★ data/ itself is a symlink, so data/shared IS the store.
# -L is false and -d is true here; classifying on those would delete the store.
setup_fixture
rm -rf "$WT/data"
ln -s ../../data "$WT/data"
run_setup
check "T6 store NOT deleted" "$(store_intact)" "yes"
check "T6 still resolves to store" "$(resolved)" "$(readlink -f "$STORE")"
teardown_fixture

# T7: refuses to run in the main repository (data/shared is the store there)
setup_fixture
(cd "$FIX/main" && bash scripts/setup-worktree.sh >/dev/null 2>&1)
check "T7 refuses in main (non-zero exit)" "$?" "1"
check "T7 store untouched" "$(store_intact)" "yes"
check "T7 no nested link in store" "$([[ -e "$STORE/shared" ]] && echo yes || echo no)" "no"
teardown_fixture

# T8: path_type=relative must produce a relative link that still resolves
setup_fixture
run_setup
check "T8 link is relative" "$(readlink "$WT/data/shared")" "../../../data/shared"
check "T8 relative link resolves to store" "$(resolved)" "$(readlink -f "$STORE")"
teardown_fixture

# T9: a broken link must fail loudly rather than report success
setup_fixture
rm -rf "$WT/data/shared" "$STORE"
run_setup
check "T9 missing store -> non-zero exit" "$?" "1"
teardown_fixture

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
