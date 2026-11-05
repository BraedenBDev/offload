#!/bin/sh
# Installs the offload skill for Claude Code. Needs only stock macOS 27 on Apple Silicon: no Xcode, git, Python or Node.
#   curl -fsSL https://raw.githubusercontent.com/BraedenBDev/offload/main/install.sh | sh
# Set OFFLOAD_TARBALL to install from another archive of this repo.
set -eu
fail() { echo "offload: $1" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "this needs macOS."
[ "$(uname -m)" = arm64 ] || fail "this needs an Apple Silicon Mac."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 27 ] || fail "this needs macOS 27 or later, and you have $(sw_vers -productVersion)."

url=${OFFLOAD_TARBALL:-https://github.com/BraedenBDev/offload/archive/refs/heads/main.tar.gz}
dest=$HOME/.claude/skills/offload
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading offload"
curl -fsSL "$url" | tar -xz -C "$tmp" --strip-components=1 || fail "could not download $url"
"$tmp/skills/offload/bin/offload" version >/dev/null || fail "the downloaded program won't run on this Mac."

mkdir -p "$HOME/.claude/skills"
if [ -e "$dest" ]; then  # kept outside skills/, where Claude Code would load it as a second skill
  rm -rf "$HOME/.claude/offload.previous"
  mv "$dest" "$HOME/.claude/offload.previous"
fi
mv "$tmp/skills/offload" "$dest"

# A convenience for your own terminal. The skill calls its binary by full path and doesn't need this.
link=$HOME/.local/bin/offload
mkdir -p "$HOME/.local/bin"
if [ -L "$link" ] || [ ! -e "$link" ]; then ln -sfn "$dest/bin/offload" "$link"; else echo "Left your existing $link alone"; fi

echo
if [ -t 1 ] && (: </dev/tty) 2>/dev/null; then
  "$dest/bin/offload" setup </dev/tty || true  # asks about each missing piece, reading answers from the terminal even when piped from curl
else
  "$dest/bin/offload" setup --yes || true
fi

echo
echo "Installed $dest"
echo "Rerun offload setup any time something is missing. Check everything with: $dest/scripts/selftest.sh"
echo "Start a new Claude Code session, then ask it to do something large."
