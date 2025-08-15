# macOS Ruby Environment Reset Script

**Version:** 2.6.0\
**Supported OS:** **macOS only** (Darwin)\
**Shell Compatibility:** Bash 3.2+ (default on macOS)

---

## TL;DR

This script **resets your Ruby environment to the default system Ruby on macOS**. It:

- Detects and **attempts** to remove version managers (`rbenv`, `rvm`, `asdf`)
- Removes all **non-system Ruby versions** and associated gems
- Cleans up **shell init files** and lingering Ruby paths
- Removes `.ruby-version` / `.tool-versions` files
- Cleans stale Homebrew taps (optional)
- Provides a **post-run audit** with instructions if anything remains

**⚠️ This script is for macOS only. Running it on other systems may break your Ruby environment.**

---

## Quick Examples

### Interactive cleanup

```bash
bash ./reset-macruby.sh
```

- Lists detected managers and Ruby installs
- Prompts before removal

### Full automation

```bash
bash ./reset-macruby.sh --full-reset
```

- Removes all Ruby installs, managers, gems, caches, and shell init entries
- Cleans Homebrew stale taps
- Shows post-run audit

### Skip removing version managers

```bash
bash ./reset-macruby.sh --full-reset --keep-managers
```

- Resets Ruby versions and gems but keeps `rbenv`, `rvm`, and `asdf`

### Dry run (preview actions)

```bash
bash ./reset-macruby.sh --dry-run
```

- Shows exactly what would happen without making changes

---

## Flags

| Flag                   | Description                                                                                                                                                 |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--dry-run`            | Show what actions would be taken without making changes                                                                                                     |
| `--full-reset`         | Remove all detected Ruby installs, attempt to remove managers, scrub shell files, clear caches, purge `.ruby-version` files, and untap stale Homebrew repos |
| `--keep-managers`      | Skip removal of `rbenv`, `rvm`, and `asdf` even if detected                                                                                                 |
| `--purge-ruby-version` | Automatically remove `.ruby-version` files without prompting                                                                                                |

---

## Post-Run Audit

After running, the script will show:

- Remaining version managers
- Their locations and binary paths
- Shell init file references
- Exact manual removal steps

**Example:**

```text
⚠️  rbenv still detected:
   • binary on PATH: /opt/homebrew/bin/rbenv
   • Homebrew formula: rbenv (installed)
   • user directory: /Users/alex/.rbenv
   • init lines in:
     /Users/alex/.zprofile:8:eval "$(rbenv init - --no-rehash zsh)"
   → Suggested removal steps:
     - brew uninstall rbenv ruby-build
     - rm -rf "/Users/alex/.rbenv"
     - sed -i '' -E '#rbenv#d' ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile
     - sed -i '' -E '#/\.rbenv/shims#d' ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile
     - exec $SHELL
```

---

## What This Script Removes

- **Ruby installs**: rbenv, rvm, asdf, Homebrew, standalone
- **Gem caches**: `~/.gem`, `~/.bundle`, `~/.cache/bundler`, `~/.rvm/gems`, `~/.rvm/gemsets`, `~/Library/Caches/ruby-build`
- **Manager directories**: `~/.rbenv`, `~/.rvm`, `~/.asdf`
- **Homebrew packages**: `rbenv`, `ruby-build`, `asdf`
- **Shell init lines** referencing managers
- `.ruby-version` and `.tool-versions` entries

---

## Notes

- Always restart your shell or run `exec $SHELL` after changes
- To check your Ruby version after reset:

```bash
which ruby && ruby -v
```

- You should see `/usr/bin/ruby` for macOS system Ruby

