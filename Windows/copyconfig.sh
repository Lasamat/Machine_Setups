#!/bin/bash

MAPPING_FILE="mapping.txt"

# Define ANSI color codes
RED='\033[0;31m'    # Red for errors
YELLOW='\033[0;33m' # Yellow for warnings
GREEN='\033[0;32m'  # Green for success
BLUE='\033[0;34m'   # Blue for active processing
NC='\033[0m'        # No color (reset)

# Function to print messages with color
print_success() { echo -e "${GREEN}Success:${NC} $1"; }
print_warning() { echo -e "${YELLOW}Warning:${NC} $1"; }
print_error() { echo -e "${RED}Error:${NC} $1"; }
print_processing() { echo -e "\n${BLUE}Processing:${NC} $1"; }

# Check if username argument is provided
if [ -z "$1" ]; then
    print_error "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1
USER_DIRECTORY="/c/Users/$USERNAME"

# Check if the Windows user directory exists
if [ ! -d "$USER_DIRECTORY" ]; then
    print_error "Windows user directory '$USER_DIRECTORY' not found! Exiting."
    exit 1
fi

print_success "Valid Windows user directory detected: $USER_DIRECTORY"

# Check if mapping file exists
if [ ! -f "$MAPPING_FILE" ]; then
    print_error "Mapping file '$MAPPING_FILE' not found! Exiting."
    exit 1
fi

# Read and process each mapping entry
while read -r SOURCE DESTINATION; do
    # Replace `{username}` in destination paths with the provided username
    DESTINATION=${DESTINATION//\{username\}/$USERNAME}

    print_processing "$SOURCE -> $DESTINATION"

    # Verify source exists
    if [ ! -e "$SOURCE" ]; then
        print_warning "Source '$SOURCE' does not exist, skipping..."
        continue
    fi

    # Ensure destination directory exists or create it
    if [ ! -d "$DESTINATION" ]; then
        print_success "Creating destination directory: $DESTINATION"
        mkdir -p "$DESTINATION"
    else
        print_warning "Cleaning up existing files in '$DESTINATION'"
        rm -rf "$DESTINATION"/*
    fi

    # Copy only folder contents recursively
    if cp -r "$SOURCE/"* "$DESTINATION/"; then
        print_success "Successfully copied all contents from '$SOURCE' to '$DESTINATION'"
    else
        print_error "Failed to copy contents from '$SOURCE' to '$DESTINATION'"
    fi

done < "$MAPPING_FILE"

print_success "All files processed successfully!"
