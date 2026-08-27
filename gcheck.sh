#!/bin/bash
set -uo pipefail

# ---------------------------------------------------------------------------
# Colors / icons (disabled automatically when not a TTY or when NO_COLOR is set)
# ---------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[0;31m'
  YELLOW=$'\033[0;33m'
  GREEN=$'\033[0;32m'
  BLUE=$'\033[0;34m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  NC=$'\033[0m'
else
  RED="" YELLOW="" GREEN="" BLUE="" BOLD="" DIM="" NC=""
fi

ICON_OK="✔"
ICON_CHANGES="✖"
ICON_SYNC="⇅"
FS=$'\x1f' # field separator used to pass results back from parallel workers

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG_DIR="$HOME/.config/gcheck"
EXCLUDE_FILE="$CONFIG_DIR/exclude_list"
BOOKMARK_DIR="$CONFIG_DIR/bookmarks"
LAST_DIR_FILE="$CONFIG_DIR/.last_dir"

TARGET_DIR="$PWD"
TARGET_EXPLICIT=0
SCAN_DEPTH=2
VERBOSE=0
USE_FZF=0
SHOW_ALL=0
NO_FETCH=0
MAX_PARALLEL=8
BOOKMARK_NAME=""
USE_BOOKMARK=""

log_debug() { [[ "$VERBOSE" -eq 1 ]] && echo -e "${BLUE}[DEBUG]${NC} $1" >&2; return 0; }
log_info()  { echo -e "${BLUE}$1${NC}"; }
log_warn()  { echo -e "${YELLOW}$1${NC}"; }
log_err()   { echo -e "${RED}$1${NC}" >&2; }

print_help() {
  cat <<EOF
Usage: $0 [--target <directory>] [--depth <level>] [options]

  --target <directory>    Directory to scan (default: current directory)
  --depth <level>         Scan depth (default: 2)
  --parallel <n>          Number of repositories checked concurrently (default: 8)
  --no-fetch              Skip 'git fetch'; only use already-known remote state (faster, offline)
  --bookmark <name>       Save the current scan as a bookmark with the given name
  --use-bookmark <name>   Use a saved bookmark to limit the scan to specific repositories
  --verbose               Show detailed debug output
  --fzf                   Filter repositories with changes using fzf and select one
  --all                   Show all repositories, including those with no issues
  --help                  Show this help message

If neither --target nor --use-bookmark is given and a bookmark named
"default" exists (see --bookmark default), it is used automatically.
EOF
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target )
      shift; [[ $# -eq 0 ]] && { log_err "Error: --target requires a value"; exit 1; }
      TARGET_DIR="$1"; TARGET_EXPLICIT=1 ;;
    --depth )
      shift; [[ $# -eq 0 ]] && { log_err "Error: --depth requires a value"; exit 1; }
      SCAN_DEPTH="$1" ;;
    --parallel )
      shift; [[ $# -eq 0 ]] && { log_err "Error: --parallel requires a value"; exit 1; }
      MAX_PARALLEL="$1" ;;
    --verbose ) VERBOSE=1 ;;
    --fzf )     USE_FZF=1 ;;
    --all )     SHOW_ALL=1 ;;
    --no-fetch ) NO_FETCH=1 ;;
    --bookmark )
      shift; [[ $# -eq 0 ]] && { log_err "Error: --bookmark requires a value"; exit 1; }
      BOOKMARK_NAME="$1" ;;
    --use-bookmark )
      shift; [[ $# -eq 0 ]] && { log_err "Error: --use-bookmark requires a value"; exit 1; }
      USE_BOOKMARK="$1" ;;
    --help )
      print_help; exit 0 ;;
    * )
      log_err "Error: Invalid argument $1"; print_help; exit 1 ;;
  esac
  shift
done

[[ "$SCAN_DEPTH" =~ ^[0-9]+$ ]] || { log_err "Error: --depth must be a positive integer"; exit 1; }
[[ "$MAX_PARALLEL" =~ ^[0-9]+$ && "$MAX_PARALLEL" -ge 1 ]] || { log_err "Error: --parallel must be a positive integer"; exit 1; }

# ---------------------------------------------------------------------------
# Setup configuration directory and files
# ---------------------------------------------------------------------------
if [[ ! -d "$CONFIG_DIR" ]]; then
  log_warn "Creating configuration directory: $CONFIG_DIR"
  mkdir -p "$CONFIG_DIR"
fi

if [[ ! -f "$EXCLUDE_FILE" ]]; then
  log_warn "Creating exclude file: $EXCLUDE_FILE"
  {
    echo "# Add directories to exclude from scanning, one per line."
    echo ".tmux"
    echo ".cargo"
    echo ".zinit"
    echo ".asdf"
  } > "$EXCLUDE_FILE"
  log_info "Exclude file created with default entries."
fi

[[ -d "$BOOKMARK_DIR" ]] || mkdir -p "$BOOKMARK_DIR"

mapfile -t excluded_dirs < <(grep -vE '^\s*(#|$)' "$EXCLUDE_FILE" 2>/dev/null || true)

# ---------------------------------------------------------------------------
# Resolve default bookmark: if the user didn't ask for a specific target or
# bookmark, fall back to a bookmark named "default" when one exists. If it
# doesn't exist, just proceed with a normal directory scan (no error).
# ---------------------------------------------------------------------------
if [[ -z "$USE_BOOKMARK" && "$TARGET_EXPLICIT" -eq 0 && -z "$BOOKMARK_NAME" ]]; then
  if [[ -f "$BOOKMARK_DIR/default" ]]; then
    USE_BOOKMARK="default"
    log_debug "No --target/--use-bookmark given; using the 'default' bookmark."
  else
    log_debug "No 'default' bookmark found; scanning '$TARGET_DIR' instead. (Tip: --bookmark default to create one.)"
  fi
fi

# ---------------------------------------------------------------------------
# Build the list of repositories to check
# ---------------------------------------------------------------------------
repos=()
if [[ -n "$USE_BOOKMARK" ]]; then
  BOOKMARK_FILE="$BOOKMARK_DIR/$USE_BOOKMARK"
  if [[ ! -f "$BOOKMARK_FILE" ]]; then
    log_err "Error: Bookmark '$USE_BOOKMARK' does not exist."
    exit 1
  fi
  log_info "Using bookmark: $USE_BOOKMARK"
  mapfile -t repos < <(grep -v '^\s*$' "$BOOKMARK_FILE" || true)
else
  if [[ ! -d "$TARGET_DIR" ]]; then
    log_err "Error: target directory '$TARGET_DIR' does not exist."
    exit 1
  fi
  log_info "Scanning directories in $TARGET_DIR with depth $SCAN_DEPTH..."
  mapfile -t found < <(find "$TARGET_DIR" -maxdepth "$SCAN_DEPTH" -type d -name ".git" 2>/dev/null | sed 's/\/\.git$//')
  for r in "${found[@]}"; do
    skip=0
    for exclude in "${excluded_dirs[@]}"; do
      [[ -n "$exclude" && "$r" == *"$exclude"* ]] && { skip=1; break; }
    done
    [[ "$skip" -eq 0 ]] && repos+=("$r")
  done
fi

# Save the current scan as a bookmark if requested, then exit
if [[ -n "$BOOKMARK_NAME" ]]; then
  printf '%s\n' "${repos[@]}" > "$BOOKMARK_DIR/$BOOKMARK_NAME"
  log_info "Bookmark '$BOOKMARK_NAME' saved successfully (${#repos[@]} repositories)."
  exit 0
fi

if [[ ${#repos[@]} -eq 0 ]]; then
  log_warn "No Git repositories found."
  exit 0
fi

# ---------------------------------------------------------------------------
# Check each repository (in parallel, isolated in subshells)
# ---------------------------------------------------------------------------
check_repo() {
  local repo="$1" repo_name branch_name git_status
  local modified untracked pull_count push_count has_upstream

  repo_name=$(basename "$repo")

  if ! cd "$repo" 2>/dev/null; then
    printf '%s\n' "${repo}${FS}${repo_name}${FS}?${FS}0${FS}0${FS}0${FS}0${FS}0"
    return
  fi

  branch_name=$(git branch --show-current 2>/dev/null)
  git_status=$(git status --short 2>/dev/null)
  untracked=$(grep -c '^??' <<<"$git_status")
  modified=$(( $(grep -c . <<<"$git_status") - untracked ))

  pull_count=0
  push_count=0
  has_upstream=0
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' &>/dev/null; then
    has_upstream=1
    [[ "$NO_FETCH" -eq 0 ]] && git fetch --quiet 2>/dev/null
    pull_count=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
    push_count=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  fi

  printf '%s\n' "${repo}${FS}${repo_name}${FS}${branch_name:-detached}${FS}${modified}${FS}${untracked}${FS}${pull_count}${FS}${push_count}${FS}${has_upstream}"
}

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

total=${#repos[@]}
SECONDS=0

(
  idx=0
  for repo in "${repos[@]}"; do
    idx=$((idx + 1))
    ( check_repo "$repo" > "$tmp_dir/$idx.out" ) &
    while [[ $(jobs -rp | wc -l) -ge "$MAX_PARALLEL" ]]; do
      wait -n 2>/dev/null || true
    done
  done
  wait
) &
scan_pid=$!

if [[ "$VERBOSE" -eq 0 && -t 1 ]]; then
  spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  i=0
  while kill -0 "$scan_pid" 2>/dev/null; do
    printf '\r%s%s%s Scanning %d repositories...' "$BLUE" "${spinner:$((i % ${#spinner})):1}" "$NC" "$total"
    i=$((i + 1))
    sleep 0.1
  done
  printf '\r\033[K'
else
  log_debug "Scanning $total repositories (parallel=$MAX_PARALLEL, fetch=$([[ $NO_FETCH -eq 0 ]] && echo on || echo off))..."
fi
wait "$scan_pid" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Parse results
# ---------------------------------------------------------------------------
d_name=() d_branch=() d_status=() d_color=() d_sev=()
repos_with_changes=()
ok_count=0
changes_count=0
sync_count=0

for ((idx = 1; idx <= total; idx++)); do
  [[ -f "$tmp_dir/$idx.out" ]] || continue
  line=$(<"$tmp_dir/$idx.out")
  IFS="$FS" read -r r_path r_name r_branch r_mod r_untr r_pull r_push r_upstream <<<"$line"

  if [[ "$r_branch" == "?" ]]; then
    log_debug "Skipping unreadable repository: $r_path"
    continue
  fi

  if [[ "$r_mod" -gt 0 || "$r_untr" -gt 0 ]]; then
    color="$RED"; icon="$ICON_CHANGES"; sev=2
    repos_with_changes+=("$r_path")
    changes_count=$((changes_count + 1))
    status_text="Modified: $r_mod  Untracked: $r_untr"
  elif [[ "$r_pull" -gt 0 || "$r_push" -gt 0 ]]; then
    color="$YELLOW"; icon="$ICON_SYNC"; sev=1
    repos_with_changes+=("$r_path")
    sync_count=$((sync_count + 1))
    status_text="Pull: $r_pull  Push: $r_push"
  else
    color="$GREEN"; icon="$ICON_OK"; sev=0
    ok_count=$((ok_count + 1))
    status_text="OK"
    [[ "$r_upstream" -eq 0 ]] && status_text="OK  (no upstream)"
  fi

  [[ "$SHOW_ALL" -eq 0 && "$sev" -eq 0 ]] && continue

  d_name+=("$r_name")
  d_branch+=("$r_branch")
  d_status+=("$icon $status_text")
  d_color+=("$color")
  d_sev+=("$sev")
done

# ---------------------------------------------------------------------------
# Render the TUI table
# ---------------------------------------------------------------------------
if [[ ${#d_name[@]} -eq 0 ]]; then
  log_info "All repositories are clean. ${ICON_OK}"
else
  # Sort: changes first, then sync-needed, then OK; alphabetical within each group
  mapfile -t order < <(
    for ((i = 0; i < ${#d_name[@]}; i++)); do
      printf '%d\t%s\t%d\n' "$((2 - d_sev[i]))" "${d_name[i],,}" "$i"
    done | sort -k1,1n -k2,2 | cut -f3
  )

  header_repo="Repository"; header_branch="Branch"; header_status="Status"
  repo_w=${#header_repo}; branch_w=${#header_branch}; status_w=${#header_status}
  for i in "${order[@]}"; do
    (( ${#d_name[i]} > repo_w )) && repo_w=${#d_name[i]}
    (( ${#d_branch[i]} > branch_w )) && branch_w=${#d_branch[i]}
    (( ${#d_status[i]} > status_w )) && status_w=${#d_status[i]}
  done

  hrule() {
    local n=$1 out=""
    for ((k = 0; k < n; k++)); do out+="─"; done
    printf '%s' "$out"
  }

  print_border() {
    local left="$1" mid="$2" right="$3"
    echo "${left}$(hrule $((repo_w + 2)))${mid}$(hrule $((branch_w + 2)))${mid}$(hrule $((status_w + 2)))${right}"
  }

  echo -e "${DIM}Legend: ${GREEN}${ICON_OK} OK${NC}${DIM}   ${YELLOW}${ICON_SYNC} sync needed${NC}${DIM}   ${RED}${ICON_CHANGES} uncommitted changes${NC}"
  print_border '╭' '┬' '╮'
  printf '│ %-*s │ %-*s │ %-*s │\n' "$repo_w" "$header_repo" "$branch_w" "$header_branch" "$status_w" "$header_status"
  print_border '├' '┼' '┤'
  for i in "${order[@]}"; do
    padded_status=$(printf '%-*s' "$status_w" "${d_status[i]}")
    printf '│ %-*s │ %-*s │ %s%s%s │\n' "$repo_w" "${d_name[i]}" "$branch_w" "${d_branch[i]}" "${d_color[i]}" "$padded_status" "$NC"
  done
  print_border '╰' '┴' '╯'
fi

echo -e "${BOLD}Scan complete:${NC} ${total} repositories — ${GREEN}${ok_count} OK${NC}, ${RED}${changes_count} with changes${NC}, ${YELLOW}${sync_count} need sync${NC}  ${DIM}(${SECONDS}s)${NC}"

# ---------------------------------------------------------------------------
# fzf selection: write the choice to a state file (a plain `cd` here would
# only affect this subprocess, not your shell — see README for a wrapper
# function that reads this file and `cd`s for you).
# ---------------------------------------------------------------------------
if [[ "$USE_FZF" -eq 1 ]]; then
  if [[ ${#repos_with_changes[@]} -eq 0 ]]; then
    log_warn "No repositories with changes to display in fzf."
  else
    selected_repo=$(printf '%s\n' "${repos_with_changes[@]}" | fzf --prompt "Select a repository: ")
    if [[ -n "$selected_repo" ]]; then
      log_info "Selected: $selected_repo"
      printf '%s' "$selected_repo" > "$LAST_DIR_FILE"
      echo -e "${DIM}Tip: use the gcheck() shell wrapper from the README to cd automatically.${NC}"
    fi
  fi
fi
