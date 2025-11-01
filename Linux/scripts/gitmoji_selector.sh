#!/bin/bash

SELECTED_EMOJI=$(cat ~/.local/scripts/gitmojis.json | jq -r '.[0].gitmojis[] | "\(.description) \(.code)"' | fzf-tmux -p --reverse --ansi | awk '{print $NF}')

if [ -n "$SELECTED_EMOJI" ]; then
  echo -n "$SELECTED_EMOJI" | xclip -selection clipboard
  echo -n "$SELECTED_EMOJI" | tmux set-buffer
fi
