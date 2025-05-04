#!bin/bash
SESH="event-sourcing"

tmux has-session -t $SESH 2>/dev/null

if [ $? != 0 ]; then
  tmux new-session -d -s $SESH -n "editor"

  tmux send-keys -t $SESH:editor "cd /mnt/g/Repository/Elixir/event-sourcing/lunar_frontiers_1 " C-m
  tmux send-keys -t $SESH:editor "nvim ." C-m

  #tmux new-window -t $SESH -n "server"
  #tmux send-keys -t $SESH:server "cd ~/projects/my_project" C-m
  #tmux send-keys -t $SESH:server "npm run dev" C-m

  tmux set-option -t $SESH status on
  tmux set-option -t $SESH status-style fg=white,bg=black
  tmux set-option -t $SESH status-left "#[fg=green]Session: #S #[fg=yellow]"
  tmux set-option -t $SESH status-left-length 40
  tmux set-option -t $SESH status-right "#[fg=cyan]%d %b %R"

  tmux set-window-option -t $SESH window-status-style fg=cyan,bg=black
  tmux set-window-option -t $SESH window-status-current-style fg=white

  tmux select-window -t $SESH:editor
fi

tmux attach-session -t $SESH
