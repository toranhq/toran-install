#!/bin/sh
# Installs the Toran binary on macOS or Linux from its package on ghcr.io (#146).
#
#   gh api -H "Accept: application/vnd.github.raw" repos/toranhq/toran/contents/scripts/install.sh | sh
#
# Without repository access, docs/install.md has the command that fetches this
# file from the package, where every release publishes it.
#
# It reads prompts from the terminal, so it also works piped. With Homebrew,
# or apt-get or dnf on Linux, it offers to install git and gh, and it offers
# to sign gh in; it may ask gh
# for one more scope, which you approve in the browser. It needs curl, a
# SHA-256 utility, gunzip and mktemp, which come with the OS, and no
# access to the Toran repository: only read access to the package, which the
# maintainer grants. It holds no secret. It reads the package with a
# registry token exchanged from your gh sign-in, the same way Toran's
# self-update does (src/update/ghcr.ts); neither token is written to disk or
# passed on a command line.
#
# It installs ~/.local/bin/toran (TORAN_BIN_DIR to put it elsewhere), and
# adds that directory to PATH in your shell's profile if it is not there,
# then runs toran setup in the same terminal. Running it again installs the
# newest release over the old one.

set -eu
TORAN_INSTALLER_RELEASE=v0.98.0

REGISTRY=https://ghcr.io
REPOSITORY=toranhq/toran
TAG=stable
CONFIG_TYPE=application/vnd.116labs.gaal.build.v1+json
SHA256_KEY='io\.github\.toranhq\.toran\.sha256'
SCOPE=read:packages
SCOPE_FIX="gh auth refresh -h github.com -s $SCOPE"
ACCESS_FIX="ask the maintainer for package access"
BIN_DIR=${TORAN_BIN_DIR:-${GAAL_BIN_DIR:-"$HOME/.local/bin"}}
[ "$BIN_DIR" = / ] || BIN_DIR=${BIN_DIR%/}

say() { printf '%s\n' "$*"; }
shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
die() {
  printf 'toran install: %s\n' "$*" >&2
  exit 1
}

# Answers come from the terminal on fd 3, since stdin is the script itself
# when piped into sh. TORAN_INSTALL_TTY stands in for the terminal in tests.
TTY=${TORAN_INSTALL_TTY:-${GAAL_INSTALL_TTY:-/dev/tty}}

try_tty() {
  [ -n "${tty_open:-}" ] && return 0
  # Probed in a subshell: a failed exec redirection ends a POSIX shell.
  (exec 3<"$TTY") 2>/dev/null || return 1
  exec 3<"$TTY"
  tty_open=yes
}
need_tty() {
  try_tty || die "this step needs a terminal: run the installer again in a terminal window"
}

ask() {
  need_tty
  printf '%s [y/N] ' "$1" >&2
  IFS= read -r answer <&3 || answer=""
  case "$answer" in y | Y | yes | Yes | YES) return 0 ;; *) return 1 ;; esac
}

run_interactive() {
  need_tty
  "$@" <&3
}

# macOS ships a git stub that only offers the developer tools, so a tool
# counts only once it runs.
tool_available() {
  command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1
}
need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is needed: $2"
}
os=$(uname -s)
machine=$(uname -m)

tmp=$(mktemp -d "${TMPDIR:-/tmp}/toran-install.XXXXXX")
part=""
cleanup() {
  rm -rf "$tmp"
  if [ -n "$part" ]; then rm -f "$part"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# gh from GitHub's package repository: a distro's gh is often older than Toran needs.
# Called under || (set -e off), so each step returns; sudo's stdin may be this script.
install_linux_tools() {
  case "$missing" in *gh*) want_gh=yes ;; *) want_gh=no ;; esac
  case "$1" in
    apt-get)
      if [ "$want_gh" = yes ]; then
        keyring=/etc/apt/keyrings/githubcli-archive-keyring.gpg
        deb_arch=$(dpkg --print-architecture) || return 1
        curl -fsSL -o "$tmp/gh.gpg" https://cli.github.com/packages/githubcli-archive-keyring.gpg </dev/null || return 1
        sudo mkdir -p -m 755 /etc/apt/keyrings </dev/null || return 1
        sudo install -m 644 "$tmp/gh.gpg" "$keyring" </dev/null || return 1
        printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' "$deb_arch" "$keyring" |
          sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null || return 1
      fi
      sudo apt-get update </dev/null || return 1
      # shellcheck disable=SC2086 # $missing is a list of tool names
      sudo apt-get install -y $missing </dev/null
      ;;
    dnf)
      if [ "$want_gh" = yes ]; then
        curl -fsSL -o "$tmp/gh-cli.repo" https://cli.github.com/packages/rpm/gh-cli.repo </dev/null || return 1
        sudo install -m 644 "$tmp/gh-cli.repo" /etc/yum.repos.d/gh-cli.repo </dev/null || return 1
      fi
      # shellcheck disable=SC2086 # $missing is a list of tool names
      sudo dnf install -y $missing </dev/null
      ;;
  esac
}

missing=""
for tool in git gh; do
  if ! tool_available "$tool"; then missing="$missing $tool"; fi
done
install_hint="brew install git gh"
if [ -n "$missing" ]; then
  manager=""
  if tool_available brew; then
    manager=brew
  elif [ "$os" = Linux ] && command -v apt-get >/dev/null 2>&1; then
    manager=apt-get
    install_hint="sudo apt-get install git gh"
  elif [ "$os" = Linux ] && command -v dnf >/dev/null 2>&1; then
    manager=dnf
    install_hint="sudo dnf install git gh"
  fi
  [ -n "$manager" ] || die "git and gh are needed: install them with your package manager (Homebrew: brew install git gh), then run this again"
  if [ "$manager" = brew ]; then
    question="Install the missing prerequisites with brew install git gh?"
  else
    question="Install$missing with $manager? This uses sudo, and adds GitHub's package repository for gh."
  fi
  ask "$question" || die "git and gh are needed: run $install_hint (gh: https://github.com/cli/cli/blob/trunk/docs/install_linux.md), then this again"
  if [ "$manager" = brew ]; then
    brew install git gh || die "could not install git and gh: run brew install git gh, then this again"
  else
    install_linux_tools "$manager" || die "could not install$missing: run $install_hint, then this again"
  fi
fi
tool_available git || die "git is needed: run $install_hint, then this again"
tool_available gh || die "gh is needed: run $install_hint, then this again"
need curl "install curl, then run this again"
need gunzip "install gzip, then run this again"

case "$os:$machine" in
  Darwin:arm64) platform=darwin; arch=arm64 ;;
  Darwin:x86_64)
    if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
      platform=darwin; arch=arm64
    else
      platform=darwin; arch=x64
    fi
    ;;
  Linux:x86_64) platform=linux; arch=x64 ;;
  Linux:aarch64) platform=linux; arch=arm64 ;;
  *) die "no Toran binary for $os $machine; see the README" ;;
esac
# By what is installed, not by OS: macOS has no sha256sum, and a Linux may have only shasum.
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
else
  die "sha256sum is needed: install coreutils, then run this again"
fi

# gh's sign-in, and the scope that reads a private package. `--active` skips
# a stale second account; gh before 2.40 has no such flag.
status=$(gh auth status --hostname github.com --active 2>&1) ||
  status=$(gh auth status --hostname github.com 2>&1) || {
    if ask "gh is not signed in to github.com. Run gh auth login now?"; then
      run_interactive gh auth login || die "gh sign-in failed: run gh auth login in a terminal, then this again"
      status=$(gh auth status --hostname github.com --active 2>&1) ||
        status=$(gh auth status --hostname github.com 2>&1) ||
        die "gh is not signed in to github.com: run gh auth login, then this again"
    else
      die "gh is not signed in to github.com: run gh auth login, then this again"
    fi
  }
# `Token scopes: 'a', 'b'`; gh before 2.40 prints them unquoted. None shown
# (a token without classic scopes): try anyway.
scopes=$(printf '%s\n' "$status" | sed -n 's/.*Token scopes:[[:space:]]*//p' | head -n 1)
# A token kept in hosts.yml stays there: gh would otherwise write the
# refresh to a keyring that may prompt on a desktop nobody sees (#909).
insecure=""
if printf '%s\n' "$status" | grep -q 'hosts\.yml)'; then
  insecure=--insecure-storage
  SCOPE_FIX="$SCOPE_FIX $insecure"
fi
case "$scopes" in
  "" | none | None) ;;
  *)
    if ! printf '%s\n' "$scopes" | tr -d "'" | tr ',' '\n' |
      sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qx "$SCOPE"; then
      if [ -z "$insecure" ] && [ -n "${SSH_CONNECTION:-}" ] && printf '%s\n' "$status" | grep -q '(keyring)'; then
        say "gh keeps its token in the keyring, which may prompt on the desktop of this machine, where this SSH session cannot see it. If the refresh hangs, stop it and run: $SCOPE_FIX --insecure-storage"
      fi
      say "gh needs the $SCOPE scope to read the Toran package. Approve it in the browser:"
      # shellcheck disable=SC2086 # $insecure is one flag or nothing
      run_interactive gh auth refresh -h github.com -s "$SCOPE" $insecure ||
        die "the scope was not added: run $SCOPE_FIX, then this again"
    fi
    ;;
esac

# GETs a small JSON document: prints its body, then its HTTP status on a
# line of its own (000 when curl could not connect). $2 is a line of curl
# config, given on stdin so a credential never appears in a process listing.
get() {
  url=$1
  config=$2
  shift 2
  printf '%s\n' "$config" | curl -sS -L -K - -w '\n%{http_code}' "$@" "$url" 2>"$tmp/curl.err" ||
    printf '\n000'
}
status_of() { printf '%s\n' "$1" | tail -n 1; }
body_of() { printf '%s\n' "$1" | sed '$d'; }
# `HTTP 404 MANIFEST_UNKNOWN`, from a registry error body when it has one.
http_error() {
  code=$(printf '%s' "$2" | sed -n 's/.*"errors":\[{"code":"\([A-Z_]*\)".*/\1/p')
  if [ "$1" = 000 ]; then
    printf 'no connection: %s' "$(head -n 1 "$tmp/curl.err")"
  elif [ -n "$code" ]; then
    printf 'HTTP %s %s' "$1" "$code"
  else
    printf 'HTTP %s' "$1"
  fi
}
refused() {
  die "no access to ghcr.io/$REPOSITORY ($1): $ACCESS_FIX; if you were granted it, give gh the $SCOPE scope: $SCOPE_FIX"
}

# A pull token for the package, exchanged from gh's token (basic auth).
gh_token=$(gh auth token --hostname github.com 2>/dev/null) || gh_token=""
[ -n "$gh_token" ] || die "gh has no github.com token: run gh auth login, then this again"
reply=$(get "$REGISTRY/token?scope=repository:$REPOSITORY:pull&service=ghcr.io" "user = \"toran:$gh_token\"")
gh_token=""
code=$(status_of "$reply")
body=$(body_of "$reply")
case "$code" in
  200) ;;
  401 | 403) die "ghcr.io refused gh's github.com sign-in ($(http_error "$code" "$body")): sign in again with gh auth login, or $ACCESS_FIX" ;;
  *) die "ghcr.io gave no registry token ($(http_error "$code" "$body"))" ;;
esac
token=$(printf '%s' "$body" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$token" ] || die "ghcr.io gave no registry token"
bearer="header = \"Authorization: Bearer $token\""

# The release's manifest.
reply=$(get "$REGISTRY/v2/$REPOSITORY/manifests/$TAG" "$bearer" -H "Accept: application/vnd.oci.image.manifest.v1+json")
code=$(status_of "$reply")
manifest=$(body_of "$reply")
case "$code" in
  200) ;;
  401 | 403 | 404) refused "$(http_error "$code" "$manifest")" ;;
  *) die "could not read ghcr.io/$REPOSITORY:$TAG ($(http_error "$code" "$manifest"))" ;;
esac
case "$manifest" in
  *"\"$CONFIG_TYPE\""*) ;;
  *) die "ghcr.io/$REPOSITORY:$TAG is not a Toran release" ;;
esac

# This Mac's layer: its digest, and the SHA-256 of the binary inside it.
# With whitespace gone and braces as line breaks, a layer's annotations are
# one line, and its other fields the lines either side of it.
flat=$(printf '%s' "$manifest" | tr -d ' \t\r\n' | tr '{' '\n' | tr '}' '\n')
# A release made before the toran- names ships its layers as gaal-.
line=""
for asset in "toran-$platform-$arch" "gaal-$platform-$arch"; do
  line=$(printf '%s\n' "$flat" | grep -n "\"org\.opencontainers\.image\.title\":\"$asset\.gz\"" | head -n 1 | cut -d: -f1)
  [ -z "$line" ] || break
done
[ -n "$line" ] || die "the release has no toran-$platform-$arch binary"
fields=$(printf '%s\n' "$flat" | sed -n "$((line - 1))p; $((line + 1))p" | tr ',' '\n')
annotations=$(printf '%s\n' "$flat" | sed -n "${line}p" | tr ',' '\n')
digest=$(printf '%s\n' "$fields" | sed -n 's/^"digest":"sha256:\([0-9a-f]\{64\}\)"$/\1/p' | head -n 1)
want=$(printf '%s\n' "$annotations" | sed -n "s/^\"$SHA256_KEY\":\"\\([0-9a-f]\\{64\\}\\)\"\$/\\1/p" | head -n 1)
if [ -z "$digest" ] || [ -z "$want" ]; then die "the release names no digest or SHA-256 for $asset"; fi

# Download (ghcr.io redirects to GitHub's storage, where curl sends no
# token), check it is the layer the manifest names, unpack, and check the
# binary against the SHA-256 its release published.
gz="$tmp/$asset.gz"
code=$(printf '%s\n' "$bearer" | curl -sS -L -K - -o "$gz" -w '%{http_code}' \
  "$REGISTRY/v2/$REPOSITORY/blobs/sha256:$digest" 2>"$tmp/curl.err") || code=000
token=""
bearer=""
case "$code" in
  200) ;;
  401 | 403 | 404) refused "$(http_error "$code" "$(cat "$gz" 2>/dev/null || true)")" ;;
  *) die "could not download $asset ($(http_error "$code" "$(cat "$gz" 2>/dev/null || true)"))" ;;
esac
got=$(sha256 "$gz")
[ "$got" = "$digest" ] || die "the download of $asset is not the layer the release names (sha256 $got); try again"

mkdir -p "$BIN_DIR"
dest="$BIN_DIR/toran"
# Beside the destination, so the rename over it is atomic.
part="$BIN_DIR/.toran.install.$$"
gunzip -c "$gz" >"$part" || die "could not unpack $asset"
got=$(sha256 "$part")
[ "$got" = "$want" ] || die "checksum mismatch: the release says $want, the binary is $got"
chmod 755 "$part"
mv -f "$part" "$dest"
part=""

if version=$("$dest" --version 2>/dev/null); then
  say "Installed $dest: $(printf '%s\n' "$version" | head -n 1)"
else
  say "Installed $dest, but it did not run."
fi
# Files fetched with curl are not quarantined, so this only shows when
# something else marked the file; clearing it is a stopgap until Toran is
# signed with a Developer ID and notarized.
if [ "$platform" = darwin ] && command -v xattr >/dev/null 2>&1 && xattr -p com.apple.quarantine "$dest" >/dev/null 2>&1; then
  say "macOS quarantined it; clear that once with: xattr -d com.apple.quarantine \"$dest\""
fi

# PATH, once, in the login shell's profile.
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    if [ "$BIN_DIR" = "$HOME/.local/bin" ]; then
      # shellcheck disable=SC2016 # written to the profile as it is, for the shell to expand
      export_line='export PATH="$HOME/.local/bin:$PATH"'
    else
      export_line="export PATH=\"$BIN_DIR:\$PATH\""
    fi
    case "${SHELL:-}" in
      */bash) profile="$HOME/.bash_profile" ;;
      *) profile="$HOME/.zprofile" ;;
    esac
    if ! grep -qsxF "$export_line" "$profile"; then
      printf '\n# toran\n%s\n' "$export_line" >>"$profile"
      say "Added $BIN_DIR to PATH in $profile."
    fi
    ;;
esac
# An npm install of Toran moves to the binary: its services re-pointed, its package removed (#825).
"$dest" move-to-binary || say "The npm install of Toran was not fully moved: fix what is said above, then run $dest move-to-binary."
old_ifs=$IFS
reported_legacy=no
IFS=:
for dir in $PATH; do
  [ -n "$dir" ] || dir=.
  [ "$dir" = / ] || dir=${dir%/}
  candidate="$dir/gaal"
  if [ "$candidate" = "$BIN_DIR/gaal" ]; then
    if [ -x "$candidate" ] && [ "$reported_legacy" = no ]; then
      say "Kept $candidate, the earlier name of this binary: nothing removes it; remove it by hand with: rm $(shell_quote "$candidate")"
      reported_legacy=yes
    fi
  elif [ -x "$candidate" ] && [ "$candidate" != "$dest" ]; then
    if [ -d "${dir%/bin}/lib/node_modules/gaal" ]; then
      say "Another Toran is on PATH: $candidate (remove it with: npm uninstall --global --prefix ${dir%/bin} gaal)"
    else
      say "Another Toran is on PATH: $candidate (remove it with: rm $(shell_quote "$candidate"))"
    fi
  fi
done
IFS=$old_ifs
say "New terminals pick up PATH from the profile."
if try_tty; then
  "$dest" setup <&3
else
  "$dest" setup </dev/null
fi
