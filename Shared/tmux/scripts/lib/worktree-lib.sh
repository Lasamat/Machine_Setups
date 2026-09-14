#!/usr/bin/env bash
# ── shared helpers for the git-worktree tmux workflow ──────────────────────
# Sourced by tmux-worktree.sh, tmux-worktree-session.sh, tmux-worktree-migrate.sh

set -euo pipefail

# ── resolve WORKTREE_ROOT (exported by tmux OS override conf) ──────────────
resolve_worktree_root() {
  if [[ -n "${WORKTREE_ROOT:-}" ]]; then
    echo "$WORKTREE_ROOT"
  elif [[ -d "/mnt/c" ]]; then
    echo "G:/Repository/Worktrees"
  else
    echo "$HOME/Repository/Worktrees"
  fi
}

# ── sanitize branch name for folder / tmux session name ────────────────────
sanitize() {
  echo "$1" | sed 's/[\/\.]/-/g; s/ /_/g; s/^-//; s/-$//'
}

# ── derive repo name from a path to any folder inside it ───────────────────
#    Walks up to the folder whose parent is $WORKTREE_ROOT (or contains .bare).
repo_name_from_path() {
  local dir="$1"
  local root
  root="$(resolve_worktree_root)"
  while [[ "$dir" != "$root" && "$dir" != "/" ]]; do
    if [[ -d "$dir/.bare" ]] || [[ -f "$dir/.git" ]]; then
      basename "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  basename "$dir"
}

# ── enumerate all bare repos under $WORKTREE_ROOT ──────────────────────────
each_repo() {
  local root
  root="$(resolve_worktree_root)"
  [[ -d "$root" ]] || return 0
  find "$root" -maxdepth 2 -name ".bare" -type d 2>/dev/null | while read bare; do
    echo "$(dirname "$bare")"
  done
}

# ── list tmux sessions whose name contains a given substring ───────────────
has_tmux_session() {
  tmux has-session -t "$1" 2>/dev/null
}
