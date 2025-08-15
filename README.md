# macOS Ruby Environment Reset Script

**Version:** 2.6.0  
**Supported OS:** macOS (Darwin)  
**Shell Compatibility:** Bash 3.2+ (default on macOS)

---

## Overview

This script **resets your Ruby environment on macOS** to the **default system Ruby**. It:

- Detects and **attempts** to remove common Ruby version managers (`rbenv`, `rvm`, `asdf`)
- Removes **non-system Ruby installations** and their associated gems
- Cleans up **shell init files** to remove Ruby manager initialization lines
- Optionally deletes `.ruby-version` and `.tool-versions` entries
- Cleans up **gem caches** and Homebrew stale taps (if applicable)
- **Post-run audit** to show:
  - What version managers are still installed
  - Where they are located
  - Which shell init files reference them
  - Exact commands to fully remove them

---

## Safety & Behavior

- The script will **never touch** the macOS system Ruby located at `/usr/bin/ruby`
- Dangerous paths such as `/` are protected from accidental removal
- Removal actions can be previewed with `--dry-run`
- For full automation, use `--full-reset` (see below)

---

## Flags

| Flag                   | Description |
|------------------------|-------------|
| `--dry-run`            | Show what actions would be taken without making changes |
| `--full-reset`         | Remove **all** detected Ruby installs, attempt to remove managers, scrub shell files, clear caches, purge `.ruby-version` files, and untap stale Homebrew repos |
| `--keep-managers`      | Skip removal of `rbenv`, `rvm`, and `asdf` even if detected |
| `--purge-ruby-version` | Automatically remove `.ruby-version` files without prompting |

---

## Usage

### Interactive Mode

```bash
bash ./reset-macruby.sh