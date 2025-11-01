#!/bin/bash

if command -v mise >/dev/null 2>&1; then
  echo "mise is already installed. So we skip it."
else
  # Install mise The front-end to your dev env
  curl https://mise.run | sh
fi

mise use --global node@22
mise use --global erlang@27.3.3
mise use --global elixir@1.18.2-otp-27
