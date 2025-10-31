#!/bin/bash

# List of packages to check
packages=("make" "gcc" "ripgrep" "unzip" "git" "xclip" "fd-find" "fzf" "curl" "jq")

# Function to check if a package is installed
is_installed() {
  dpkg -l | grep -qw "$1"
}

# Flag to determine if we need to run 'apt update'
needs_update=false

# Check each package
for pkg in "${packages[@]}"; do
  if ! is_installed "$pkg"; then
    echo "$pkg is not installed."
    needs_update=true
  else
    echo "$pkg is already installed."
  fi
done

# Update package list if needed
if $needs_update; then
  echo "Running apt update..."
  sudo apt update

  # Install missing packages
  for pkg in "${packages[@]}"; do
    if ! is_installed "$pkg"; then
      echo "Installing $pkg..."
      sudo apt install -y "$pkg"
    fi
  done
else
  echo "All packages are already installed."
fi
