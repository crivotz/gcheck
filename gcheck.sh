#!/bin/bash
set -uo pipefail
shopt -s extglob

# ---------------------------------------------------------------------------
# Colors / icons / themes (disabled automatically when not a TTY or when
# NO_COLOR is set). Only the status colors change between themes — the box
# border always stays a neutral gray, so switching themes never gets loud.
# ---------------------------------------------------------------------------
COLOR_ENABLED=0
[[ -t 1 && -z "${NO_COLOR:-}" ]] && COLOR_ENABLED=1

THEMES="default monokai catppuccin tokyonight gruvbox dracula nord"
THEME_NAME="default"

apply_theme() {
  local theme="$1"
  if [[ "$COLOR_ENABLED" -eq 0 ]]; then
    RED="" YELLOW="" GREEN="" BLUE="" CYAN="" BORDER="" BOLD="" DIM="" NC=""
    return
  fi
  BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
  BORDER=$'\033[38;2;73;73;73m'
  case "$theme" in
    monokai)
      RED=$'\033[38;2;249;38;114m'; GREEN=$'\033[38;2;166;226;46m'
      YELLOW=$'\033[38;2;230;219;116m'; BLUE=$'\033[38;2;174;129;255m'
      CYAN=$'\033[38;2;102;217;239m' ;;
    catppuccin)
      RED=$'\033[38;2;243;139;168m'; GREEN=$'\033[38;2;166;227;161m'
      YELLOW=$'\033[38;2;249;226;175m'; BLUE=$'\033[38;2;137;180;250m'
      CYAN=$'\033[38;2;137;220;235m' ;;
    tokyonight)
      RED=$'\033[38;2;247;118;142m'; GREEN=$'\033[38;2;158;206;106m'
      YELLOW=$'\033[38;2;224;175;104m'; BLUE=$'\033[38;2;122;162;247m'
      CYAN=$'\033[38;2;125;207;255m' ;;
    gruvbox)
      RED=$'\033[38;2;251;73;52m'; GREEN=$'\033[38;2;184;187;38m'
      YELLOW=$'\033[38;2;250;189;47m'; BLUE=$'\033[38;2;131;165;152m'
      CYAN=$'\033[38;2;142;192;124m' ;;
    dracula)
      RED=$'\033[38;2;255;85;85m'; GREEN=$'\033[38;2;80;250;123m'
      YELLOW=$'\033[38;2;241;250;140m'; BLUE=$'\033[38;2;189;147;249m'
      CYAN=$'\033[38;2;139;233;253m' ;;
    nord)
      RED=$'\033[38;2;191;97;106m'; GREEN=$'\033[38;2;163;190;140m'
      YELLOW=$'\033[38;2;235;203;139m'; BLUE=$'\033[38;2;129;161;193m'
      CYAN=$'\033[38;2;136;192;208m' ;;
    default|*)
      RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
      BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m' ;;
  esac
}
apply_theme "$THEME_NAME"

ICON_OK="✔"
ICON_CHANGES="✖"
FS=$'\x1f' # field separator used to pass results back from parallel workers

# Strip ANSI color escapes before measuring/padding so colored cell text
# (branch names, ahead/behind counts, status) still lines up in the table.
# ✔/✖ render as ordinary single-width glyphs in every terminal we've tested
# against, so plain codepoint count (no wide-character compensation) is the
# correct width here.
strip_ansi() {
  local s="$1"
  s="${s//$'\x1b'\[+([0-9;])m/}"
  printf '%s' "$s"
}

display_width() {
  local str
  str=$(strip_ansi "$1")
  printf '%d' "${#str}"
}

pad_field() {
  local str="$1" target="$2" w pad
  w=$(display_width "$str")
  pad=$((target - w))
  (( pad < 0 )) && pad=0
  printf '%s%*s' "$str" "$pad" ""
}

pad_field_right() {
  local str="$1" target="$2" w pad
  w=$(display_width "$str")
  pad=$((target - w))
  (( pad < 0 )) && pad=0
  printf '%*s%s' "$pad" "" "$str"
}

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
THEME_ARG=""
LIST_THEMES=0
FULL_PATH=0

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
  --theme <name>          Set and persist the color theme (default, monokai, catppuccin,
                          tokyonight, gruvbox, dracula, nord)
  --list-themes           List available color themes and exit
  --full-path             Show the full path instead of just the repository name
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
    --theme )
      shift; [[ $# -eq 0 ]] && { log_err "Error: --theme requires a value"; exit 1; }
      THEME_ARG="$1" ;;
    --list-themes ) LIST_THEMES=1 ;;
    --full-path )   FULL_PATH=1 ;;
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
# Resolve and apply the color theme: --theme overrides and persists it,
# otherwise fall back to the last saved theme, otherwise "default".
# ---------------------------------------------------------------------------
THEME_FILE="$CONFIG_DIR/theme"
if [[ -n "$THEME_ARG" ]]; then
  THEME_NAME="$THEME_ARG"
  if [[ " $THEMES " != *" $THEME_NAME "* ]]; then
    log_err "Error: unknown theme '$THEME_NAME'. Available: $THEMES"
    exit 1
  fi
  printf '%s\n' "$THEME_NAME" > "$THEME_FILE"
elif [[ -f "$THEME_FILE" ]]; then
  THEME_NAME=$(<"$THEME_FILE")
fi

if [[ "$LIST_THEMES" -eq 1 ]]; then
  echo "Available themes (current marked with *):"
  for t in $THEMES; do
    apply_theme "$t"
    marker=" "; [[ "$t" == "$THEME_NAME" ]] && marker="*"
    printf ' %s %s%-11s%s %s%s%s %s%s%s\n' "$marker" "$BOLD" "$t" "$NC" "$GREEN" "$ICON_OK" "$NC" "$RED" "$ICON_CHANGES" "$NC"
  done
  exit 0
fi

apply_theme "$THEME_NAME"

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
d_name=() d_branch=() d_status=() d_status_color=() d_ahead=() d_behind=() d_sev=()
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
    sev=2; status_color="$RED"
    status_text="${ICON_CHANGES} Modified: $r_mod  Untracked: $r_untr"
    repos_with_changes+=("$r_path")
    changes_count=$((changes_count + 1))
  elif [[ "$r_pull" -gt 0 || "$r_push" -gt 0 ]]; then
    sev=1; status_color="$GREEN"; status_text="${ICON_OK} clean"
    repos_with_changes+=("$r_path")
    sync_count=$((sync_count + 1))
  else
    sev=0; status_color="$GREEN"; status_text="${ICON_OK} OK"
    [[ "$r_upstream" -eq 0 ]] && status_text="${ICON_OK} OK (no upstream)"
    ok_count=$((ok_count + 1))
  fi

  [[ "$SHOW_ALL" -eq 0 && "$sev" -eq 0 ]] && continue

  if [[ "$r_upstream" -eq 1 ]]; then
    ahead_val="$r_push"; behind_val="$r_pull"
  else
    ahead_val="-"; behind_val="-"
  fi

  if [[ "$FULL_PATH" -eq 1 ]]; then
    d_name+=("$r_path")
  else
    d_name+=("$r_name")
  fi
  d_branch+=("$r_branch")
  d_status+=("$status_text")
  d_status_color+=("$status_color")
  d_ahead+=("$ahead_val")
  d_behind+=("$behind_val")
  d_sev+=("$sev")
done

# ---------------------------------------------------------------------------
# Render: a single bordered window, ahead/behind as their own colored
# columns, and a category breakdown inside the box instead of one line after it.
# ---------------------------------------------------------------------------
hrule() {
  local n=$1 out=""
  for ((k = 0; k < n; k++)); do out+="─"; done
  printf '%s' "$out"
}

draw_top_title() {
  local width="$1" text="$2" dw left right
  dw=$(display_width "$text")
  left=$(( (width - dw) / 2 ))
  right=$(( width - dw - left ))
  printf '%s╭%s%s%s%s╮%s\n' "$BORDER" "$(hrule "$left")" "$text" "$BORDER" "$(hrule "$right")" "$NC"
}

draw_sep() { printf '%s├%s┤%s\n' "$BORDER" "$(hrule "$1")" "$NC"; }
draw_bottom() { printf '%s╰%s╯%s\n' "$BORDER" "$(hrule "$1")" "$NC"; }

draw_row() {
  local text="$1" width="$2" padded
  padded=$(pad_field "$text" $((width - 2)))
  printf '%s│%s %s %s│%s\n' "$BORDER" "$NC" "$padded" "$BORDER" "$NC"
}

if [[ ${#d_name[@]} -eq 0 ]]; then
  log_info "All repositories are clean. ${ICON_OK}"
else
  # Sort: changes first, then sync-needed, then OK; alphabetical within each group
  mapfile -t order < <(
    for ((i = 0; i < ${#d_name[@]}; i++)); do
      printf '%d\t%s\t%d\n' "$((2 - d_sev[i]))" "${d_name[i],,}" "$i"
    done | sort -k1,1n -k2,2 | cut -f3
  )

  header_repo="Repository"; header_branch="Branch"; header_ahead="Ahead"; header_behind="Behind"; header_status="Status"
  repo_w=$(display_width "$header_repo"); branch_w=$(display_width "$header_branch")
  ahead_w=$(display_width "$header_ahead"); behind_w=$(display_width "$header_behind")
  status_w=$(display_width "$header_status")
  for i in "${order[@]}"; do
    w=$(display_width "${d_name[i]}"); (( w > repo_w )) && repo_w=$w
    w=$(display_width "${d_branch[i]}"); (( w > branch_w )) && branch_w=$w
    w=$(display_width "${d_ahead[i]}"); (( w > ahead_w )) && ahead_w=$w
    w=$(display_width "${d_behind[i]}"); (( w > behind_w )) && behind_w=$w
    w=$(display_width "${d_status[i]}"); (( w > status_w )) && status_w=$w
  done

  header_row="$(pad_field "$header_repo" "$repo_w")  $(pad_field "$header_branch" "$branch_w")  $(pad_field_right "$header_ahead" "$ahead_w")  $(pad_field_right "$header_behind" "$behind_w")  $(pad_field "$header_status" "$status_w")"

  data_rows=()
  for i in "${order[@]}"; do
    name_f=$(pad_field "${d_name[i]}" "$repo_w")
    branch_f=$(pad_field "${CYAN}${d_branch[i]}${NC}" "$branch_w")
    ahead_color="$DIM"; [[ "${d_ahead[i]}" != "-" && "${d_ahead[i]}" -gt 0 ]] && ahead_color="$GREEN"
    behind_color="$DIM"; [[ "${d_behind[i]}" != "-" && "${d_behind[i]}" -gt 0 ]] && behind_color="$RED"
    ahead_f=$(pad_field_right "${ahead_color}${d_ahead[i]}${NC}" "$ahead_w")
    behind_f=$(pad_field_right "${behind_color}${d_behind[i]}${NC}" "$behind_w")
    status_f=$(pad_field "${d_status_color[i]}${d_status[i]}${NC}" "$status_w")
    data_rows+=("${name_f}  ${branch_f}  ${ahead_f}  ${behind_f}  ${status_f}")
  done

  summary_label_w=0
  for lbl in "Healthy" "Attention" "Sync needed"; do
    w=$(display_width "$lbl"); (( w > summary_label_w )) && summary_label_w=$w
  done
  summary_rows=(
    "$(pad_field "${GREEN}Healthy${NC}" "$summary_label_w")   ${ok_count}"
    "$(pad_field "${RED}Attention${NC}" "$summary_label_w")   ${changes_count}  (uncommitted changes)"
    "$(pad_field "${YELLOW}Sync needed${NC}" "$summary_label_w")   ${sync_count}  (ahead/behind remote)"
  )

  box_w=0
  for r in "$header_row" "${data_rows[@]}" "${summary_rows[@]}"; do
    w=$(display_width "$r"); (( w + 2 > box_w )) && box_w=$((w + 2))
  done
  title=" ${BOLD}gcheck${NC} "
  title_w=$(display_width "$title"); (( title_w + 2 > box_w )) && box_w=$((title_w + 2))

  echo -e "${DIM}Legend: ${GREEN}${ICON_OK} OK${NC}${DIM}   ${RED}${ICON_CHANGES} uncommitted changes${NC}${DIM}   ${GREEN}ahead${NC}${DIM}/${RED}behind${NC}${DIM} = commits to push/pull${NC}"
  draw_top_title "$box_w" "$title"
  draw_row "$header_row" "$box_w"
  draw_sep "$box_w"
  for row in "${data_rows[@]}"; do
    draw_row "$row" "$box_w"
  done
  draw_sep "$box_w"
  for row in "${summary_rows[@]}"; do
    draw_row "$row" "$box_w"
  done
  draw_bottom "$box_w"
fi

echo -e "${DIM}Scanned ${total} repositories in ${SECONDS}s (theme: ${THEME_NAME})${NC}"

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
