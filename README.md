# gcheck

**gcheck** is a Bash script that scans directories for Git repositories, checks their status, and provides a visual summary using colors to indicate the status of each repository. The script also offers advanced features like saving scans as bookmarks, using `fzf` to select repositories, and customizing the scan depth.

---

## Features

- **Scan Git Directories**: Scans directories to find Git repositories up to a configurable depth.
- **Visual Summary**:
  - **Green**: Repositories with no issues (OK).
  - **Red**: Modified, untracked, or uncommitted files.
  - **Yellow**: Repositories requiring a push or pull.
- **Bookmarks**:
  - Save the list of scanned repositories as a bookmark.
  - Use bookmarks to limit scans to specific repositories.
- **Exclude Directories**: Exclude specific directories from scans using a configuration file.
- **`fzf` Support**: Filter repositories with changes and select one to open in the shell.
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

---

## Output

The script generates a tabular summary with the following details:

| Repository                  | Branch              | Status                                         |
|-----------------------------|---------------------|-----------------------------------------------|
| `my-repo`                   | `main`             | **Green**: OK                                 |
| `another-repo`              | `develop`          | **Red**: Modified: 2, Untracked: 1           |
| `yet-another-repo`          | `feature-x`        | **Yellow**: Push: 1, Pull: 2                  |

---

## Configuration

Configuration files are located in the `~/.config/gcheck` directory:
- **Exclude List**: `exclude_list` — contains directories to exclude from scans.
- **Bookmark Directory**: `bookmarks/` — contains saved bookmark files.

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
