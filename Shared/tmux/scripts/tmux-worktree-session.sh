#!/usr/bin/env bash
# ── create or attach to a 5-window tmux session for a worktree ─────────────
# Usage: tmux-worktree-session.sh <worktree-folder-path>
#
# Idempotent: if the session already exists, attach to it.
# Windows: 1:neovim  2:lazygit  3:run  4:lazysql  5:opencode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/worktree-lib.sh"

FOLDER_PATH="${1:?Usage: tmux-worktree-session.sh <worktree-folder-path>}"
FOLDER_PATH="$(cd "$FOLDER_PATH" && pwd)"

SESSION="$(sanitize "$(basename "$FOLDER_PATH")")"

if has_tmux_session "$SESSION"; then
  tmux switch-client -t "$SESSION" 2>/dev/null || tmux attach-session -t "$SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION" -c "$FOLDER_PATH" -n "neovim"
tmux send-keys -t "$SESSION:neovim" "nvim ." C-m

tmux new-window -t "$SESSION" -c "$FOLDER_PATH" -n "lazygit"
tmux send-keys -t "$SESSION:lazygit" "lazygit" C-m

tmux new-window -t "$SESSION" -c "$FOLDER_PATH" -n "run"

tmux new-window -t "$SESSION" -c "$FOLDER_PATH" -n "lazysql"
tmux send-keys -t "$SESSION:lazysql" "lazysql" C-m

tmux new-window -t "$SESSION" -c "$FOLDER_PATH" -n "opencode"
tmux send-keys -t "$SESSION:opencode" "opencode" C-m

tmux select-window -t "$SESSION:neovim"
tmux switch-client -t "$SESSION" 2>/dev/null || tmux attach-session -t "$SESSION"
