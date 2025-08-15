#!/usr/bin/env bash
set -euo pipefail

VERSION="2.6.0"  # macOS/Bash 3.2 compatible

# ---------- Flags ----------
DRY_RUN=0
FULL_RESET=0
KEEP_MANAGERS=0
PURGE_RUBY_VERSION=0   # auto-delete .ruby-version files under CWD without prompting

for arg in "$@"; do
  case "$arg" in
    --dry-run)             DRY_RUN=1 ;;
    --full-reset)          FULL_RESET=1 ;;
    --keep-managers)       KEEP_MANAGERS=1 ;;
    --purge-ruby-version)  PURGE_RUBY_VERSION=1 ;;
    *) echo "Unknown flag: $arg"; exit 2 ;;
  esac
done

# ---------- Helpers ----------
say() { printf "%s\n" "$*"; }
do_cmd() { if ((DRY_RUN)); then say "[dry-run] $*"; else eval "$@"; fi; }

do_rm() {
  local p="$1"
  [[ -n "$p" && "$p" != "/" ]] || { say "REFUSE: dangerous path '$p'"; return 1; }
  if ((DRY_RUN)); then say "[dry-run] rm -rf \"$p\""; else rm -rf "$p"; fi
}
sudo_rm_rf() {
  local p="$1"
  [[ -n "$p" && "$p" != "/" ]] || { say "REFUSE: dangerous path '$p'"; return 1; }
  if ((DRY_RUN)); then say "[dry-run] sudo rm -rf \"$p\""; else sudo rm -rf "$p"; fi
}

# BSD sed safe line scrubber (uses '#' delimiter so '/' in regex is fine)
strip_lines() {
  local file="$1" regex="$2"
  [[ -f "$file" ]] || return 0
  local safe_regex="${regex//\#/\\#}"
  if ((DRY_RUN)); then
    say "[dry-run] scrub '$regex' from $file"
  else
    sed -i '' -E "#$safe_regex#d" "$file"
  fi
}

strip_tool_versions_ruby() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if ((DRY_RUN)); then
    say "[dry-run] remove ruby line from $file"
  else
    sed -i '' -E '/^[[:space:]]*ruby(\s|$)/d' "$file"
  fi
}

brew_has() { command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -q "^$1$"; }
brew_uninstall_if_present() {
  local formula="$1"
  command -v brew >/dev/null 2>&1 || return 0
  if (( EUID == 0 )); then
    say "Skipping 'brew uninstall $formula' (running as root)."
    return 0
  fi
  if brew_has "$formula"; then
    say "Uninstalling Homebrew $formula"
    do_cmd "brew uninstall $formula || true"
  fi
}

# Small helper: check & print matching lines if file exists
print_grep_matches() {
  local file="$1" regex="$2"
  [[ -f "$file" ]] || return 0
  grep -nE "$regex" "$file" 2>/dev/null || true
}

# ---------- Target user/home ----------
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(eval echo \"~${TARGET_USER}\")"

if [[ "$OSTYPE" != darwin* ]]; then
  say "This script is intended for macOS."; exit 1
fi

say "----------------------------------------"
say " macOS Ruby Reset Script v${VERSION}"
say "----------------------------------------"
say "Target user: ${TARGET_USER}"
say "Target home: ${TARGET_HOME}"
say "Dry run: $DRY_RUN   Full reset: $FULL_RESET   Keep managers: $KEEP_MANAGERS"
say "----------------------------------------"

# ---------- Detect managers (dir OR PATH OR Homebrew) ----------
RBENV_DIR="${TARGET_HOME}/.rbenv"
RVM_DIR="${TARGET_HOME}/.rvm"
ASDF_DIR="${TARGET_HOME}/.asdf"

MANAGERS=()
if command -v rbenv >/dev/null 2>&1 || brew_has rbenv || [[ -d "$RBENV_DIR" ]]; then MANAGERS+=("rbenv"); fi
if command -v rvm   >/dev/null 2>&1 || [[ -d "$RVM_DIR" ]]; then MANAGERS+=("rvm"); fi
if command -v asdf  >/dev/null 2>&1 || brew_has asdf  || [[ -d "$ASDF_DIR" ]]; then MANAGERS+=("asdf"); fi
# de-dup (Bash 3.2-safe; items contain no spaces)
if ((${#MANAGERS[@]})); then MANAGERS=($(printf "%s\n" "${MANAGERS[@]}" | awk '!seen[$0]++')); fi

say "🔎 Detected managers: ${MANAGERS[*]:-none}"

# ---------- Collect installs ----------
INSTALL_LABELS=()
INSTALL_PATHS=()

if [[ -d "$RBENV_DIR/versions" ]]; then
  while IFS= read -r -d '' vdir; do
    INSTALL_LABELS+=("rbenv $(basename "$vdir")")
    INSTALL_PATHS+=("$vdir")
  done < <(find "$RBENV_DIR/versions" -mindepth 1 -maxdepth 1 -type d -print0)
fi
if [[ -d "$RVM_DIR/rubies" ]]; then
  while IFS= read -r -d '' vdir; do
    INSTALL_LABELS+=("rvm $(basename "$vdir")")
    INSTALL_PATHS+=("$vdir")
  done < <(find "$RVM_DIR/rubies" -mindepth 1 -maxdepth 1 -type d -print0)
fi
if [[ -d "$ASDF_DIR/installs/ruby" ]]; then
  while IFS= read -r -d '' vdir; do
    INSTALL_LABELS+=("asdf $(basename "$vdir")")
    INSTALL_PATHS+=("$vdir")
  done < <(find "$ASDF_DIR/installs/ruby" -mindepth 1 -maxdepth 1 -type d -print0)
fi

detect_standalone() {
  local d="$1" label="$2"
  [[ -x "$d/bin/ruby" ]] || return 0
  INSTALL_LABELS+=("$label $(basename "$d")")
  INSTALL_PATHS+=("$d")
}
detect_standalone "/opt/homebrew/opt/ruby" "homebrew"
detect_standalone "/usr/local/opt/ruby"    "homebrew"
detect_standalone "/usr/local/ruby"        "standalone"
detect_standalone "/opt/ruby"              "standalone"
detect_standalone "${TARGET_HOME}/.rubies" "standalone"

say "----------------------------------------"
if ((${#INSTALL_PATHS[@]}==0)); then
  say "No non-system Ruby installations found."
else
  say "Found Ruby installations:"
  for i in "${!INSTALL_PATHS[@]}"; do
    printf "  %2d) %-16s %s\n" "$((i+1))" "${INSTALL_LABELS[$i]}" "${INSTALL_PATHS[$i]}"
  done
fi
say "----------------------------------------"

# ---------- Choose removal ----------
REMOVE_ALL=0
SELECTED_INDEXES=()

if (( FULL_RESET )); then
  REMOVE_ALL=1
else
  if ((${#INSTALL_PATHS[@]} > 0)); then
    read -r -p "1) Remove all  2) Select specific  3) Skip : " choice
    case "${choice:-}" in
      1) REMOVE_ALL=1 ;;
      2)
        read -r -p "Enter numbers (e.g. 1 3 4): " selections
        for sel in $selections; do
          if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#INSTALL_PATHS[@]} )); then
            SELECTED_INDEXES+=($((sel-1)))
          else
            say "Skipping invalid selection: $sel"
          fi
        done
        ;;
      *) ;;
    esac
  fi
fi

remove_install_by_index() {
  local idx="$1" label="${INSTALL_LABELS[$idx]}" path="${INSTALL_PATHS[$idx]}"
  say "→ Removing $label [$path]"
  case "$label" in
    rbenv\ *) command -v rbenv >/dev/null 2>&1 && do_cmd "rbenv uninstall -f \"${label#rbenv }\" || true"; do_rm "$path" ;;
    rvm\ *)   command -v rvm   >/dev/null 2>&1 && do_cmd "rvm uninstall \"${label#rvm }\" || rvm remove \"${label#rvm }\" || true"; do_rm "$path" ;;
    asdf\ *)  command -v asdf  >/dev/null 2>&1 && do_cmd "asdf uninstall ruby \"${label#asdf }\" || true"; do_rm "$path" ;;
    homebrew\ *|standalone\ *) [[ "$path" == /opt/* || "$path" == /usr/* ]] && sudo_rm_rf "$path" || do_rm "$path" ;;
    * )       do_rm "$path" ;;
  esac
}

if (( REMOVE_ALL )); then
  for i in "${!INSTALL_PATHS[@]}"; do remove_install_by_index "$i"; done
elif ((${#SELECTED_INDEXES[@]} > 0)); then
  for i in "${SELECTED_INDEXES[@]}"; do remove_install_by_index "$i"; done
fi

# ---------- Gem/cache cleanup ----------
if (( FULL_RESET )) || { read -r -p "Remove gem caches? (y/n): " ans && [[ "$ans" == y ]]; }; then
  for d in \
    "${TARGET_HOME}/.gem" \
    "${TARGET_HOME}/.bundle" \
    "${TARGET_HOME}/.cache/bundler" \
    "${TARGET_HOME}/Library/Caches/ruby-build" \
    "${RVM_DIR}/gems" \
    "${RVM_DIR}/gemsets"
  do
    [[ -e "$d" ]] && do_rm "$d"
  done
fi

# ---------- Manager removal (dirs + Homebrew + init scrub) ----------
REMOVE_MANAGERS="n"
if (( FULL_RESET )) && (( KEEP_MANAGERS == 0 )); then
  REMOVE_MANAGERS="y"
elif ((${#MANAGERS[@]})); then
  read -r -p "Attempt to remove version managers (${MANAGERS[*]})? (y/n): " REMOVE_MANAGERS
fi

if [[ "$REMOVE_MANAGERS" == "y" ]]; then
  # rbenv: dir + brew formulas
  [[ -d "$RBENV_DIR" ]] && { say "Removing $RBENV_DIR"; do_rm "$RBENV_DIR"; }
  brew_uninstall_if_present "rbenv"
  brew_uninstall_if_present "ruby-build"

  # rvm
  [[ -d "$RVM_DIR" ]] && { say "Removing $RVM_DIR"; do_rm "$RVM_DIR"; }

  # asdf: ruby plugin/installs/shims + asdf itself (and brew asdf)
  if [[ -d "$ASDF_DIR" ]] || command -v asdf >/dev/null 2>&1 || brew_has asdf; then
    [[ -d "$ASDF_DIR/installs/ruby" ]] && { say "Removing $ASDF_DIR/installs/ruby"; do_rm "$ASDF_DIR/installs/ruby"; }
    [[ -d "$ASDF_DIR/plugins/ruby"  ]] && { say "Removing $ASDF_DIR/plugins/ruby";  do_rm "$ASDF_DIR/plugins/ruby";  }
    [[ -d "$ASDF_DIR/shims"         ]] && { say "Removing $ASDF_DIR/shims";         do_rm "$ASDF_DIR/shims";         }
    [[ -d "$ASDF_DIR"               ]] && { say "Removing $ASDF_DIR";               do_rm "$ASDF_DIR";               }
    brew_uninstall_if_present "asdf"
  fi
fi

# Always scrub init lines if FULL_RESET or user says yes
if (( FULL_RESET )) || { read -r -p "Scrub shell init files? (y/n): " SCRUB && [[ "$SCRUB" == y ]]; }; then
  for f in "${TARGET_HOME}/.zshrc" "${TARGET_HOME}/.zprofile" "${TARGET_HOME}/.bash_profile" "${TARGET_HOME}/.bashrc"; do
    strip_lines "$f" 'rbenv'
    strip_lines "$f" 'RBENV_SHELL'
    strip_lines "$f" '/\.rbenv/shims'
    strip_lines "$f" '(^|\s)rvm(|\.)'
    strip_lines "$f" 'ASDF_DIR|asdf\.sh|asdf\.fish'
    # remove init blocks like: eval "$(rbenv init - --no-rehash zsh)"
    strip_lines "$f" 'eval "\$\((| )rbenv init([^"]*)\)"'
  done
  strip_tool_versions_ruby "${TARGET_HOME}/.tool-versions"
fi

# Optional: purge .ruby-version files under current directory
if (( FULL_RESET )); then
  if (( PURGE_RUBY_VERSION )); then
    say "Purging .ruby-version files under: $(pwd)"
    if ((DRY_RUN)); then find . -name '.ruby-version' -print; else find . -name '.ruby-version' -delete; fi
  else
    read -r -p "Remove any '.ruby-version' files under the current directory? (y/n): " PURGE_Q
    if [[ "${PURGE_Q:-n}" == "y" ]]; then
      if ((DRY_RUN)); then find . -name '.ruby-version' -print; else find . -name '.ruby-version' -delete; fi
    fi
  fi
fi

# ---------- Homebrew stale tap cleanup (full reset only) ----------
if (( FULL_RESET )); then
  if command -v brew >/dev/null 2>&1 && (( EUID != 0 )); then
    if brew tap | grep -q '^homebrew/cask-versions$'; then
      say "Untapping stale Homebrew tap: homebrew/cask-versions"
      do_cmd "brew untap homebrew/cask-versions || true"
    fi
  fi
fi

# ---------- POST-RUN AUDIT & GUIDANCE ----------
say "----------------------------------------"
say "Post-run audit (what's still installed & how to remove it):"

audit_manager() {
  local name="$1" bin="" has_brew="no" user_dir=""
  case "$name" in
    rbenv)
      bin="$(command -v rbenv 2>/dev/null || true)"
      brew_has rbenv && has_brew="yes" || has_brew="no"
      [[ -d "$RBENV_DIR" ]] && user_dir="$RBENV_DIR" || user_dir=""
      ;;
    rvm)
      bin="$(command -v rvm 2>/dev/null || true)"
      has_brew="no"   # RVM isn't managed by Homebrew normally
      [[ -d "$RVM_DIR" ]] && user_dir="$RVM_DIR" || user_dir=""
      ;;
    asdf)
      bin="$(command -v asdf 2>/dev/null || true)"
      brew_has asdf && has_brew="yes" || has_brew="no"
      [[ -d "$ASDF_DIR" ]] && user_dir="$ASDF_DIR" || user_dir=""
      ;;
  esac

  if [[ -z "$bin" && "$has_brew" = "no" && -z "$user_dir" ]]; then
    say "✓ $name: not detected"
    return 0
  fi

  say ""
  say "⚠️  $name still detected:"
  [[ -n "$bin" ]]      && say "   • binary on PATH: $bin"
  [[ "$has_brew" = yes ]] && say "   • Homebrew formula: $name (installed)"
  [[ -n "$user_dir" ]] && say "   • user directory: $user_dir"

  # show init lines that might re-enable it
  local init_hits=""
  init_hits="$(
    print_grep_matches "${TARGET_HOME}/.zshrc"     "$name|\\.$name/shims" ;
    print_grep_matches "${TARGET_HOME}/.zprofile"  "$name|\\.$name/shims" ;
    print_grep_matches "${TARGET_HOME}/.bashrc"    "$name|\\.$name/shims" ;
    print_grep_matches "${TARGET_HOME}/.bash_profile" "$name|\\.$name/shims"
  )"
  if [[ -n "$init_hits" ]]; then
    say "   • init lines found in shell startup files:"
    printf "%s\n" "$init_hits"
  fi

  say "   → Suggested removal steps:"
  case "$name" in
    rbenv)
      [[ "$has_brew" = yes ]] && say "     - brew uninstall rbenv ruby-build"
      [[ -n "$user_dir"    ]] && say "     - rm -rf \"$user_dir\""
      say "     - sed -i '' -E '#rbenv#d' ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile ; sed -i '' -E '#/\\.rbenv/shims#d' ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile"
      ;;
    rvm)
      [[ -n "$user_dir"    ]] && say "     - rm -rf \"$user_dir\""
      say "     - sed -i '' -E '#rvm#d' ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile"
      ;;
    asdf)
      [[ "$has_brew" = yes ]] && say "     - brew uninstall asdf"
      [[ -n "$user_dir"    ]] && say "     - rm -rf \"$user_dir\""
      say "     - sed -i '' -E '#asdf|ASDF_DIR#d' ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile"
      say "     - rm -f ~/.tool-versions  # or remove the 'ruby' line from it"
      ;;
  esac
  say "     - exec \$SHELL   # or open a new terminal"
}

audit_manager "rbenv"
audit_manager "rvm"
audit_manager "asdf"

say "----------------------------------------"
say "Reset complete for user: ${TARGET_USER}"
say "System Ruby remains available at /usr/bin/ruby"
say "----------------------------------------"