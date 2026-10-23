# shellcheck shell=bash
#
# Where the shared store is, and when it is safe to delete something near it.
#
# The same config key (shared_data_path) used to be read relative to the main
# repository by one script and relative to the current directory by another --
# and one of them decides what to delete. This file is the single definition.
#
# In a derived project the whole store (~26 GB) was destroyed and replaced by a
# relative link written into the main repository, although a main-repo guard and
# a `cd` into the worktree were already in place. So these checks are meant to be
# re-run *immediately before* each destructive operation, not once at the top.
#
# Usage:
#   . "$MAIN_REPO/scripts/lib/shared-store.sh"

# Absolute path of the shared store. The single definition -- every script that
# needs it calls this rather than joining paths itself.
shared_store_path() {
    local main_repo="$1" config rel
    config="$main_repo/.claude/worktree-config.json"
    [ -f "$config" ] || { echo "shared-store: config not found: $config" >&2; return 1; }
    if command -v jq >/dev/null 2>&1; then
        rel=$(jq -r '.shared_data_path' "$config")
    else
        rel=$(grep '"shared_data_path"' "$config" | cut -d'"' -f4)
    fi
    if [ -z "$rel" ] || [ "$rel" = "null" ]; then
        echo "shared-store: shared_data_path is unset in $config" >&2
        return 1
    fi
    # Always resolved against the main repository. `path_type: relative` describes
    # the *link* written into a worktree, not where the store lives.
    printf '%s\n' "$main_repo/$rel"
}

# The store must be a real directory. If it has become a symlink or vanished,
# every downstream path computation is meaningless -- and that is exactly the
# shape the data loss above left behind, so callers should check first.
assert_store_intact() {
    local store="$1"
    if [ -L "$store" ]; then
        echo "shared-store: the store is a SYMLINK, not a directory: $store -> $(readlink "$store")" >&2
        echo "  This is the shape a past data loss left behind. Refusing to continue." >&2
        return 1
    fi
    if [ ! -d "$store" ]; then
        echo "shared-store: the store does not exist: $store" >&2
        echo "  Run ./scripts/init-data.sh in the main repository first." >&2
        return 1
    fi
    return 0
}

# Re-assert, at the moment of deletion, that `target` is not the store and that
# we are standing where this run thinks it is standing.
#
#   target       what is about to be removed (relative to the current directory)
#   store        absolute path of the shared store
#   expected_cwd the worktree this run was configured for
#   main_repo    the main repository
#
# A check made a hundred lines earlier does not protect this deletion: the
# working directory, the store path and the worktree path can all drift in
# between. Only a check that still holds now does.
assert_safe_to_delete() {
    local target="$1" store="$2" expected_cwd="$3" main_repo="$4"
    local here resolved
    here=$(pwd -P)
    resolved=$(readlink -f "$target" 2>/dev/null || true)

    if [ -n "$resolved" ] && [ "$resolved" = "$(readlink -f "$store" 2>/dev/null)" ]; then
        echo "shared-store: refusing to delete '$target': it IS the shared store." >&2
        echo "  $target -> $resolved" >&2
        return 1
    fi
    if [ "$here" = "$(readlink -f "$main_repo")" ]; then
        echo "shared-store: refusing to delete '$target': the working directory is the" >&2
        echo "  main repository, where data/shared is the store itself. pwd -> $here" >&2
        return 1
    fi
    if [ -n "$expected_cwd" ] && [ "$here" != "$(readlink -f "$expected_cwd")" ]; then
        echo "shared-store: refusing to delete '$target': the working directory is not" >&2
        echo "  the worktree this run is configured for." >&2
        echo "  pwd      -> $here" >&2
        echo "  expected -> $(readlink -f "$expected_cwd")" >&2
        return 1
    fi
    return 0
}
