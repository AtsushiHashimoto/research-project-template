#!/usr/bin/env bash
# Tests for scripts/lib/shared-store.sh -- the store's location and the checks
# that stand between a script and a destructive operation.
#
# A past incident in a derived project destroyed the store and left it replaced by
# a worktree-depth relative link. The mechanism was never established, so these
# tests pin the *detection* of that shape rather than any one cause.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/shared-store.sh
. "$REPO_ROOT/scripts/lib/shared-store.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

fixture() {
    FIX=$(mktemp -d)
    mkdir -p "$FIX/main/.claude" "$FIX/main/data/shared/datasets" "$FIX/main/worktrees/wt/data"
    echo '{"version":"1.1","shared_data_path":"data/shared","path_type":"relative"}' \
        > "$FIX/main/.claude/worktree-config.json"
    echo STORE > "$FIX/main/data/shared/datasets/marker.txt"
}
cleanup() { rm -rf "$FIX"; }
trap '[ -n "${FIX:-}" ] && rm -rf "$FIX"' EXIT

echo "=== shared-store.sh ==="

# ---------------------------------------------------------------- location
fixture
got=$(shared_store_path "$FIX/main")
check "the store is resolved against the main repository" "$got" "$FIX/main/data/shared"

# The bug this replaces: safe-remove-worktree.sh read the same key as relative to
# the current directory, so the answer moved with the caller.
cd "$FIX/main/worktrees/wt" || exit 1
got=$(shared_store_path "$FIX/main")
check "the answer does not depend on the caller's directory" "$got" "$FIX/main/data/shared"
cd "$REPO_ROOT" || exit 1

shared_store_path "$FIX/nonexistent" >/dev/null 2>&1
check "a missing config is an error, not an empty path" "$?" "1"

# An external store (init-data.sh writes an absolute path for it) is used as is
echo '{"shared_data_path":"/srv/store","path_type":"absolute"}' > "$FIX/main/.claude/worktree-config.json"
check "an absolute shared_data_path is used as is" "$(shared_store_path "$FIX/main")" "/srv/store"
cleanup

# ------------------------------------------------------------ store intact
fixture
assert_store_intact "$FIX/main/data/shared" >/dev/null 2>&1
check "a real directory passes" "$?" "0"

# The exact shape the incident left behind: a worktree-depth relative link, dangling.
rm -rf "$FIX/main/data/shared"
ln -s ../../../data/shared "$FIX/main/data/shared"
assert_store_intact "$FIX/main/data/shared" >/dev/null 2>&1
check "a store replaced by a dangling symlink is rejected" "$?" "1"

# The worse variant: a link that *does* resolve. Every write still succeeds, it
# just lands somewhere else, so nothing complains until the data is looked for.
# A test using only the dangling case cannot tell whether the symlink check works
# -- "not a directory" catches that one on its own (found by mutation testing).
rm -f "$FIX/main/data/shared"
mkdir -p "$FIX/elsewhere"
ln -s "$FIX/elsewhere" "$FIX/main/data/shared"
assert_store_intact "$FIX/main/data/shared" >/dev/null 2>&1
check "a store replaced by a symlink to a real directory is rejected" "$?" "1"

rm -f "$FIX/main/data/shared"
assert_store_intact "$FIX/main/data/shared" >/dev/null 2>&1
check "a missing store is rejected" "$?" "1"
cleanup

# --------------------------------------------------------- safe to delete
fixture
STORE="$FIX/main/data/shared"
WT="$FIX/main/worktrees/wt"

cd "$WT" || exit 1
mkdir -p data/shared
assert_safe_to_delete "data/shared" "$STORE" "$WT" "$FIX/main" >/dev/null 2>&1
check "deleting a worktree-local directory is allowed" "$?" "0"
# A target that cannot be resolved cannot be shown not to be the store: refuse (fail closed)
assert_safe_to_delete "no-such-dir/shared" "$STORE" "$WT" "$FIX/main" >/dev/null 2>&1
check "an unresolvable target is refused" "$?" "1"

# data/ pointing back into the main repository makes data/shared *be* the store
# while looking like an ordinary directory (-L false, -d true).
rm -rf "$WT/data"
ln -s ../../data "$WT/data"
assert_safe_to_delete "data/shared" "$STORE" "$WT" "$FIX/main" >/dev/null 2>&1
check "deleting the store through a symlinked data/ is refused" "$?" "1"

# Standing in the main repository, data/shared is the store itself.
cd "$FIX/main" || exit 1
assert_safe_to_delete "data/shared" "$STORE" "$WT" "$FIX/main" >/dev/null 2>&1
check "deleting from the main repository is refused" "$?" "1"
# ...even when the target is not the store (only the main-repository check can refuse this)
mkdir -p "$FIX/main/scratch"
assert_safe_to_delete "scratch" "$STORE" "" "$FIX/main" >/dev/null 2>&1
check "any deletion from the main repository is refused" "$?" "1"

# A relative path computed for one worktree, applied from another directory, is
# the shape the incident left behind.
mkdir -p "$FIX/main/worktrees/other/data/shared"
cd "$FIX/main/worktrees/other" || exit 1
assert_safe_to_delete "data/shared" "$STORE" "$WT" "$FIX/main" >/dev/null 2>&1
check "deleting from a directory other than the configured worktree is refused" "$?" "1"

cd "$REPO_ROOT" || exit 1
cleanup

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
