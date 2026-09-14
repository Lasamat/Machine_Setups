#!/usr/bin/env bash
# ── migrate an existing plain clone into the bare+worktree layout ──────────
# Usage: tmux-worktree-migrate.sh <path-to-existing-clone> [path-to-another-clone ...]
#
# Safe by design:
#   • aborts if the existing repo has uncommitted changes (commit/stash first)
#   • re-clones --bare from the existing repo's own remote (old copy untouched)
#   • creates a worktree for the branch you were on, then opens the session
#   • the old directory is left alone — delete it manually once verified

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/worktree-lib.sh"

WORKTREE_ROOT="$(resolve_worktree_root)"
mkdir -p "$WORKTREE_ROOT"
WORKTREE_ROOT="$(cd "$WORKTREE_ROOT" && pwd)"

migrate_one() {
  local src="$1"
  src="$(cd "$src" && pwd)"

  echo "── Migrating: $src"

  # sanity: must be a git repo
  if ! git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  ! Not a git repository, abort." >&2
    return 1
  fi

  # sanity: working tree must be clean (no automatic magic)
  if [[ -n "$(git -C "$src" status --porcelain)" ]]; then
    echo "  ! Working tree is dirty — commit or stash first, abort." >&2
    return 1
  fi

  local remote_url current_branch
  remote_url="$(git -C "$src" config --get remote.origin.url || echo "")"
  current_branch="$(git -C "$src" branch --show-current || echo "")"
  if [[ -z "$remote_url" ]]; then
    echo "  ! No remote 'origin' found — cannot re-clone, abort." >&2
    return 1
  fi
  [[ -n "$current_branch" ]] || current_branch="main"

  local reponame="$(basename "$src")"
  local repo="$WORKTREE_ROOT/$reponame"


  if [[ -d "$repo/.bare" ]]; then
    echo "  ! Already migrated ($repo/.bare exists), switching into it." >&2
  else
    echo "  • cloning bare from $remote_url"
    mkdir -p "$repo"
    git clone --bare "$remote_url" "$repo/.bare"
    git --git-dir="$repo/.bare" config --bool core.bare false
    echo "gitdir: $repo/.bare" > "$repo/.git"
    git --git-dir="$repo/.bare" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git --git-dir="$repo/.bare" fetch origin --prune 2>/dev/null || true
    git --git-dir="$repo/.bare" remote set-head origin -a 2>/dev/null || true
    git --git-dir="$repo/.bare" for-each-ref --format='%(refname)' refs/heads | while read -r r; do
      git --git-dir="$repo/.bare" update-ref -d "$r"
    done
    git --git-dir="$repo/.bare" symbolic-ref HEAD refs/heads/worktree-root
    git --git-dir="$repo/.bare" remote set-url --push origin "$remote_url" 2>/dev/null || true
  fi

  local target="$repo/$(sanitize "$current_branch")"
  if [[ ! -d "$target" ]]; then
    echo "  • creating worktree for $current_branch"
    git --git-dir="$repo/.bare" worktree add -b "$current_branch" "$target" "origin/$current_branch" 2>/dev/null \
      || git --git-dir="$repo/.bare" worktree add -b "$current_branch" "$target"
  fi

  echo "  ✓ done. Old directory preserved: $src"
  echo "    verify and delete manually when happy."
  bash "$SCRIPT_DIR/tmux-worktree-session.sh" "$target"
}

[[ $# -gt 0 ]] || { echo "Usage: $0 <path-to-existing-clone> [...]" >&2; exit 1; }

for arg in "$@"; do
  migrate_one "$arg"
done