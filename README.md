# gcheck

**gcheck** is a Bash script that scans directories for Git repositories, checks their status, and provides a visual summary using colors to indicate the status of each repository. The script also offers advanced features like saving scans as bookmarks, using `fzf` to select repositories, and customizing the scan depth.

---

## Features

- **Scan Git Directories**: Scans directories to find Git repositories up to a configurable depth (spaces in paths are handled correctly).
- **Parallel Scanning**: Repositories are checked concurrently (`--parallel`, default 8) with a spinner while scanning.
- **TUI Table**: Box-drawing table with dynamically sized columns, status icons (✔ OK, ✖ changes, ⇅ sync needed) and a legend. Colors and icons are automatically disabled when output isn't a terminal or `NO_COLOR` is set.
- **Sorted Output**: Repositories with uncommitted changes are shown first, then those needing sync, then (with `--all`) clean ones — alphabetically within each group.
- **Summary Line**: Total repositories scanned, counts per status, and elapsed time.
- **Bookmarks**:
  - Save the list of scanned repositories as a bookmark.
  - Use bookmarks to limit scans to specific repositories.
  - A bookmark named `default` is used automatically when neither `--target` nor `--use-bookmark` is given; if it doesn't exist, the current directory is scanned as usual.
- **Exclude Directories**: Exclude specific directories from scans using a configuration file.
- **`--no-fetch`**: Skip `git fetch` for a faster, offline-friendly scan.
- **`fzf` Support**: Filter repositories with changes and select one (see [Opening the selected repository](#opening-the-selected-repository) to actually `cd` into it).
- **Verbose Mode**: Adds detailed logs during script execution.

---

## Installation

### Prerequisites

Make sure you have:
- **Bash** installed on your system.
- **fzf** (optional) for interactive repository selection.

### Installation Steps

1. Clone this repository:
   ```bash
   git clone https://github.com/crivotz/gcheck.git
   cd gcheck
   ```

2. Make the script executable:
   ```bash
   chmod +x gcheck.sh
   ```

3. Optionally, add the script to your `$PATH`:
   ```bash
   echo "export PATH=\$PATH:$(pwd)" >> ~/.bashrc
   source ~/.bashrc
   ```

---

## Usage

Run the script with one of the following options:

### Basic Commands

- **Scan the current directory**:
  ```bash
  ./gcheck.sh
  ```

- **Specify a target directory**:
  ```bash
  ./gcheck.sh --target /path/to/dir
  ```

- **Set the scan depth**:
  ```bash
  ./gcheck.sh --depth 3
  ```

### Bookmarks

- **Save a scan as a bookmark**:
  ```bash
  ./gcheck.sh --bookmark <bookmark_name>
  ```

- **Use a saved bookmark**:
  ```bash
  ./gcheck.sh --use-bookmark <bookmark_name>
  ```

### Excluding Directories

Edit the file `~/.config/gcheck/exclude_list` to add directories to exclude (one per line).

### Advanced Options

- **Show all repositories (including those with no issues)**:
  ```bash
  ./gcheck.sh --all
  ```

- **Enable verbose mode**:
  ```bash
  ./gcheck.sh --verbose
  ```

- **Use `fzf` to select repositories with changes**:
  ```bash
  ./gcheck.sh --fzf
  ```

- **Skip network calls (no `git fetch`)**:
  ```bash
  ./gcheck.sh --no-fetch
  ```

- **Control scan concurrency**:
  ```bash
  ./gcheck.sh --parallel 16
  ```

### Opening the selected repository

A script running as a subprocess can't change the directory of the shell that
launched it, so `--fzf` writes the chosen repository path to
`~/.config/gcheck/.last_dir` instead of `cd`-ing directly. Add this function
to your `~/.bashrc` / `~/.zshrc` to get automatic `cd` behavior:

```bash
gcheck() {
  local last="$HOME/.config/gcheck/.last_dir"
  command gcheck.sh "$@"
  if [[ -f "$last" ]]; then
    cd "$(cat "$last")" || return
    rm -f "$last"
  fi
}
```

Then use `gcheck --fzf` instead of calling the script directly.

---

## Output

The script prints a box-drawing table with a legend, one row per repository,
and a summary line:

```
Legend: ✔ OK   ⇅ sync needed   ✖ uncommitted changes
╭───────────────┬───────────┬─────────────────────────────╮
│ Repository    │ Branch    │ Status                      │
├───────────────┼───────────┼─────────────────────────────┤
│ another-repo  │ develop   │ ✖ Modified: 2  Untracked: 1 │
│ yet-another   │ feature-x │ ⇅ Pull: 2  Push: 1          │
│ my-repo       │ main      │ ✔ OK                        │
╰───────────────┴───────────┴─────────────────────────────╯
Scan complete: 3 repositories — 1 OK, 1 with changes, 1 need sync  (1s)
```

Repositories with changes are listed first, then those needing a sync, then
(with `--all`) clean ones. Colors and icons are skipped automatically when
output isn't a terminal (e.g. piped to a file) or when `NO_COLOR` is set.

---

## Configuration

Configuration files are located in the `~/.config/gcheck` directory:
- **Exclude List**: `exclude_list` — contains directories to exclude from scans.
- **Bookmark Directory**: `bookmarks/` — contains saved bookmark files. A bookmark named `default` is loaded automatically when the script is run without `--target` or `--use-bookmark`.
- **`.last_dir`**: written by `--fzf` with the selected repository path (see [Opening the selected repository](#opening-the-selected-repository)).

---

## Contribution

1. Fork the repository.
2. Create a branch for your changes:
   ```bash
   git checkout -b feature/new-feature
   ```
3. Commit your changes:
   ```bash
   git commit -m "Add new feature"
   ```
4. Push the branch:
   ```bash
   git push origin feature/new-feature
   ```
5. Open a pull request on GitHub.

---

## License

This project is distributed under the [MIT License](LICENSE).
