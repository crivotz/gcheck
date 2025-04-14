#!/bin/bash

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

# Configuration variables
CONFIG_DIR="$HOME/.config/gcheck"
EXCLUDE_FILE="$CONFIG_DIR/exclude_list"
BOOKMARK_DIR="$CONFIG_DIR/bookmarks"
TARGET_DIR="$PWD"         # Default directory (current)
SCAN_DEPTH=2              # Default depth
VERBOSE=0                 # Verbose mode is disabled by default
USE_FZF=0
SHOW_ALL=0                # By default, do not show "OK" repositories
BOOKMARK_NAME=""
USE_BOOKMARK=""

# Temporary array to store repositories with changes for FZF
repos_with_changes=()

# Debug function
function log_debug() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo -e "${BLUE}[DEBUG] $1${NC}"
  fi
}

# Help function
function print_help() {
  echo "Usage: $0 [--target <directory>] [--depth <level>] [--verbose] [--fzf] [--all]"
  echo "   --target <directory>    Specify the directory to scan (default: current directory)."
  echo "   --depth <level>         Specify the scan depth (default: 2)"
  echo "   --bookmark <name>       Save the current scan as a bookmark with the given name."
  echo "   --use-bookmark <name>   Use a saved bookmark to limit the scan to specific repositories."
  echo "   --verbose               Show detailed output"
  echo "   --fzf                   Filter results using fzf and open the selected folder"
  echo "   --all                   Show all repositories, including those without issues"
  echo "   --help                  Show this help message"
}

# Parse arguments
while [[ "$1" != "" ]]; do
  case $1 in
    --target ) shift
               TARGET_DIR="$1"
               ;;
    --depth )  shift
               SCAN_DEPTH="$1"
               ;;
    --verbose ) VERBOSE=1
               ;;
    --fzf )    USE_FZF=1
               ;;
    --all )    SHOW_ALL=1
               ;;
    --bookmark ) shift
                 BOOKMARK_NAME="$1"
                 ;;
    --use-bookmark ) shift
                     USE_BOOKMARK="$1"
                     ;;
    --help )   print_help
               exit 0
               ;;
    * )        echo -e "${RED}Error: Invalid argument $1${NC}"
               print_help
               exit 1
  esac
  shift
done

# Setup configuration directory and files
if [ ! -d "$CONFIG_DIR" ]; then
  echo -e "${YELLOW}Creating configuration directory: $CONFIG_DIR${NC}"
  mkdir -p "$CONFIG_DIR"
fi

if [ ! -f "$EXCLUDE_FILE" ]; then
  echo -e "${YELLOW}Creating exclude file: $EXCLUDE_FILE${NC}"
  echo -e "# Add directories to exclude from scanning, one per line." > "$EXCLUDE_FILE"
  echo ".tmux" >> "$EXCLUDE_FILE"
  echo ".cargo" >> "$EXCLUDE_FILE"
  echo ".zinit" >> "$EXCLUDE_FILE"
  echo ".asdf" >> "$EXCLUDE_FILE"
  echo -e "${GREEN}Exclude file created with default entries.${NC}"
fi

if [ ! -d "$BOOKMARK_DIR" ]; then
  echo -e "${YELLOW}Creating bookmark directory: $BOOKMARK_DIR${NC}"
  mkdir -p "$BOOKMARK_DIR"
fi

# Load excluded directories
excluded_dirs=()
if [ -f "$EXCLUDE_FILE" ]; then
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != "#"* ]] && excluded_dirs+=("$line")
  done < "$EXCLUDE_FILE"
fi

# If using a bookmark, load repositories from the bookmark file
if [[ -n "$USE_BOOKMARK" ]]; then
  BOOKMARK_FILE="$BOOKMARK_DIR/$USE_BOOKMARK"
  if [ ! -f "$BOOKMARK_FILE" ]; then
    echo -e "${RED}Error: Bookmark '$USE_BOOKMARK' does not exist.${NC}"
    exit 1
  fi
  echo -e "${BLUE}Using bookmark: $USE_BOOKMARK${NC}"
  repos=$(cat "$BOOKMARK_FILE")
else
  # Scan directories for Git repositories
  echo -e "${BLUE}Scanning directories in $TARGET_DIR with depth $SCAN_DEPTH...${NC}"
  repos=$(find "$TARGET_DIR" -maxdepth "$SCAN_DEPTH" -type d -name ".git" | sed 's/\/.git$//')

  # Exclude directories
  for exclude in "${excluded_dirs[@]}"; do
    repos=$(echo "$repos" | grep -v "$exclude")
  done
fi

# Save the current scan as a bookmark if requested
if [[ -n "$BOOKMARK_NAME" ]]; then
  BOOKMARK_FILE="$BOOKMARK_DIR/$BOOKMARK_NAME"
  echo "$repos" > "$BOOKMARK_FILE"
  echo -e "${GREEN}Bookmark '$BOOKMARK_NAME' saved successfully.${NC}"
  exit 0
fi

# Check Git status for each repository
for repo in $repos; do
  cd "$repo" || continue

  # Repository name
  repo_name=$(basename "$repo")

  # Current branch name
  branch_name=$(git branch --show-current 2>/dev/null)

  # Repository status
  git_status=$(git status --short)

  # Check for modified files, files to commit, or files to stash
  modified_files=$(echo "$git_status" | grep -E "^( M|M | A|A | D|D )" | wc -l)
  untracked_files=$(echo "$git_status" | grep -E "^\?\?" | wc -l)

  # Check for updates to push or pull
  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)

  # Determine the color based on the status
  if [[ "$modified_files" -gt 0 || "$untracked_files" -gt 0 ]]; then
    status_color="${RED}" # Red: Uncommitted changes
    repos_with_changes+=("$repo") # Add to repos_with_changes array
  elif [[ "$ahead" -gt 0 || "$behind" -gt 0 ]]; then
    status_color="${YELLOW}" # Yellow: Push or Pull needed
    repos_with_changes+=("$repo") # Add to repos_with_changes array
  else
    status_color="${GREEN}" # Green: No issues
  fi

  # Skip "OK" repositories unless --all is specified
  if [[ "$SHOW_ALL" -eq 0 && "$modified_files" -eq 0 && "$untracked_files" -eq 0 && "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
    continue
  fi

  # Output results in table format
  printf "| %-30s | %-20s | ${status_color}Modified: %2d  Untracked: %2d  Push: %2d  Pull: %2d${NC} |\n" \
    "$repo_name" "$branch_name" "$modified_files" "$untracked_files" "$ahead" "$behind"
done

# If FZF is enabled, pass only repositories with changes to FZF
if [[ "$USE_FZF" -eq 1 ]]; then
  if [[ ${#repos_with_changes[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No repositories with changes to display in FZF.${NC}"
  else
    selected_repo=$(printf "%s\n" "${repos_with_changes[@]}" | fzf --prompt "Select a repository with changes: ")
    if [[ -n "$selected_repo" ]]; then
      echo -e "${GREEN}Opening directory: $selected_repo${NC}"
      eval "cd $selected_repo"
    fi
  fi
fi

echo -e "${GREEN}Scan completed.${NC}"
