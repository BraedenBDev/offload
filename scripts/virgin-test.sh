#!/bin/zsh
# Proves a fresh install needs nothing beyond stock macOS and Claude Code. Run it through `make virgin`.
# Installs from a tarball of the files git would ship, inside a sandbox that blocks Xcode, the developer tools,
# Homebrew, your Claude config and this repo. Add --live to also have a real Claude session use the plugin.
# It can't hide what macOS daemons already downloaded, so models this Mac has count as present. The exit code is the number of failures.
REPO=${0:A:h:h}; R=$(mktemp -d); R=${R:A}; V=$HOME/.local/bin/claude; V=${V:A}
trap 'rm -rf $R' EXIT
cd $REPO || exit 99
git ls-files -co --exclude-standard | while read -r f; do [[ -e $f ]] && print -r -- $f; done > $R/files
COPYFILE_DISABLE=1 tar -czf $R/offload.tar.gz -s ',^,offload-main/,' -T $R/files || exit 99
mkdir -p $R/home/.local/bin $R/tmp $R/repo
tar -xzf $R/offload.tar.gz -C $R/repo --strip-components=1
ln -s $V $R/home/.local/bin/claude  # the one thing a fresh Claude Code install does provide
cp install.sh $R/install.sh
cat > $R/inner.zsh <<'INNER'
R=$1; F=0
c() { if print -r -- "$2" | grep -q -- "$3"; then echo "PASS $1"; else echo "FAIL $1 (got: ${2[1,160]})"; F=$((F+1)); fi; }
gone() { if "$@" >/dev/null 2>&1; then echo "FAIL blocked: $1 still works, so this test proves nothing"; F=$((F+1)); else echo "PASS blocked: $1"; fi; }
cd $R/tmp

echo "== This really is a bare Mac"
for t in git python3 swift make clang; do gone $t --version; done
for t in brew node npx offload; do c "absent: $t" "$(whence $t || echo absent)" absent; done
c 'stock: curl' "$(curl --version | head -1)" curl; c 'stock: tar' "$(tar --version)" bsdtar; c 'stock: jq' "$(jq --version)" jq

echo "== curl install script"
curl -fsSL file://$R/install.sh | OFFLOAD_TARBALL=file://$R/offload.tar.gz sh > $R/install.log 2>&1; c 'install exit' "$?" '^0$'; c 'install ran setup' "$(cat $R/install.log)" 'Everything offload needs is ready\|missing'
S=$HOME/.claude/skills/offload
c 'skill in place' "$(ls $S/SKILL.md)" SKILL.md
c 'skill only, no repo' "$(ls $S | tr '\n' ' ')" '^SKILL.md bin fixtures references scripts $'
c 'binary runs' "$($S/bin/offload version)" '^[0-9]'
c 'no quarantine' "$(ls -l@ $S/bin/offload | grep -c quarantine)" '^0$'
c 'terminal link' "$($HOME/.local/bin/offload version)" '^[0-9]'
echo "-- self-test from the installed skill"; $S/scripts/selftest.sh; c 'installed self-test' "$?" '^0$'
cat > $R/nomodels <<NOMODELS
#!/bin/sh
if [ "\$1" = doctor ]; then echo "ready    ocr, look: built into macOS"; echo "text model: unavailable."; echo "translate to en, installed: "; exit 0; fi
exec "$S/bin/offload" "\$@"
NOMODELS
chmod +x $R/nomodels; OFFLOAD=$R/nomodels $S/scripts/selftest.sh > $R/skip.log 2>&1; c 'settings off: no failures' "$?" '^0$'; c 'settings off: 3 skips' "$(grep -c '^SKIP' $R/skip.log)" '^3$'
curl -fsSL file://$R/install.sh | OFFLOAD_TARBALL=file://$R/offload.tar.gz sh > /dev/null 2>&1; c 'reinstall exit' "$?" '^0$'
c 'reinstall keeps previous outside skills' "$(ls -d $HOME/.claude/offload.previous)" previous
c 'one skill loaded' "$(ls $HOME/.claude/skills | wc -l)" '^ *1$'
OFFLOAD_TARBALL=file://$R/none.tar.gz sh $R/install.sh >/dev/null 2>&1; c 'bad download fails' "$?" '^1$'; c 'bad download keeps skill' "$(ls $S/SKILL.md)" SKILL.md
rm -rf $HOME/.claude/skills/offload $HOME/.claude/offload.previous $HOME/.local/bin/offload

echo "== Claude Code plugin from a local marketplace"
claude=$HOME/.local/bin/claude
$claude plugin marketplace add $R/repo > $R/m.log 2>&1; c 'marketplace add' "$?" '^0$'
$claude plugin install offload@offload > $R/p.log 2>&1; c 'plugin install' "$?" '^0$'
B=$(find $HOME/.claude/plugins $R/repo -path '*skills/offload/bin/offload' 2>/dev/null | head -1)
c 'plugin carries the binary' "$($B version)" '^[0-9]'
echo "-- self-test from the plugin"; ${B:h:h}/scripts/selftest.sh; c 'plugin self-test' "$?" '^0$'
echo "== GitHub marketplace with no git on this Mac (information only)"
$claude plugin marketplace add BraedenBDev/offload 2>&1 | tail -3 | cut -c1-200

echo "failures: $F"; exit $F
INNER
PROFILE="(version 1)(allow default)
(deny file-read* file-write* (subpath \"/opt/homebrew\") (subpath \"/usr/local\") (subpath \"/Library/Developer\") (regex #\"^/Applications/Xcode\")
  (subpath \"$HOME/.claude\") (literal \"$HOME/.claude.json\") (subpath \"$HOME/.local/bin\") (subpath \"$HOME/Developer\") (subpath \"$HOME/Library/Developer\"))"
# DEVELOPER_DIR makes the stub tools fail with an error, where a real bare Mac would offer to install them.
sandbox-exec -p "$PROFILE" /usr/bin/env -i HOME=$R/home PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=$R/tmp DEVELOPER_DIR=/nonexistent TERM=dumb /bin/zsh -f $R/inner.zsh $R
F=$?

echo "== Claude Code plugin through a real git clone, for people who have git"
G=$R/git; H=$R/githome; mkdir -p $G $H $R/mk/.claude-plugin
tar -cf - -C $R/repo . | tar -xf - -C $G
git -C $G init -q -b main; git -C $G add .; git -C $G -c user.name=t -c user.email=t@t commit -qm x
print -r -- "{\"name\":\"t\",\"owner\":{\"name\":\"t\"},\"plugins\":[{\"name\":\"offload\",\"source\":{\"source\":\"url\",\"url\":\"file://$G\"}}]}" > $R/mk/.claude-plugin/marketplace.json
env HOME=$H $V plugin marketplace add $R/mk >/dev/null 2>&1; env HOME=$H $V plugin install offload@t >/dev/null 2>&1
C=$(find $H/.claude/plugins/cache -path '*skills/offload/bin/offload' 2>/dev/null | head -1)
if [[ -x $C ]] && ${C:h:h}/scripts/selftest.sh >/dev/null 2>&1; then echo "PASS cloned plugin self-test"; else echo "FAIL cloned plugin self-test"; F=$((F+1)); fi

if [[ ${1:-} == --live ]]; then
  echo "== A real Claude session, with the plugin and no offload on PATH (spends a little allowance)"
  L=$(cd $R/tmp && env PATH=/usr/bin:/bin:/usr/sbin:/sbin $V -p --model haiku --setting-sources '' --strict-mcp-config --plugin-dir $R/repo --allowedTools 'Bash Skill' --output-format stream-json --verbose \
    "Use the offload skill to read the text in $R/repo/skills/offload/fixtures/text.png, then reply with that text." </dev/null 2>/dev/null)
  U=$(print -r -- "$L" | jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="tool_use" and .name=="Bash")|.input.command')
  A=$(print -r -- "$L" | jq -r 'select(.type=="result")|.result')
  echo "-- Claude ran: ${U[1,200]}"; echo "-- Claude said: ${A[1,200]}"
  if print -r -- "$U" | grep -q 'skills/offload/bin/offload'; then echo "PASS live: Claude ran the bundled binary"; else echo "FAIL live: Claude didn't run the bundled binary"; F=$((F+1)); fi
  if print -r -- "$A" | grep -q 'OFFLOAD TEST 2027'; then echo "PASS live: Claude got the text"; else echo "FAIL live: no text in the reply"; F=$((F+1)); fi
fi
echo "total failures: $F"; exit $F
