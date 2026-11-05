#!/bin/zsh
# Checks that every offload command works, using only what's in this skill folder and stock macOS.
# Run it after a fresh install and after a macOS update. The exit code is the number of failures.
# Add --live to also send one row to Claude, which spends a tiny part of your allowance.
# Set OFFLOAD to test another build of the binary.
HERE=${0:A:h}; O=${OFFLOAD:-$HERE/../bin/offload}; O=${O:A}
offload() { "$O" "$@"; }
cd "$HERE/../fixtures" || exit 99
T=$(mktemp -d); F=0; K=0
c() { if print -r -- "$2" | grep -qi -- "$3"; then echo "PASS $1"; else echo "FAIL $1"; F=$((F+1)); fi; }
s() { echo "SKIP $1: $2"; K=$((K+1)); }
printf '{"id":"a","text":"Hola mundo, esto es una prueba de la herramienta"}\n' > $T/es.jsonl
printf '{"id":"a","text":"Tim Cook visited https://apple.com on March 3 2027"}\n' > $T/en.jsonl
D=$(offload doctor 2>/dev/null); c doctor "$D" 'text model'

# Reading
c ocr "$(offload ocr text.png 2>/dev/null)" 'OFFLOAD TEST'
c barcode "$(offload look --ops barcode qr.png 2>/dev/null)" 'example.com/offload'
c similar "$(offload similar --max-distance 5 text.png qr.png 2>/dev/null)" 'distance'
c doc "$(offload doc text.png 2>/dev/null)" 'OFFLOAD'
c transcribe "$(offload transcribe speech.wav 2>/dev/null)" 'speech test'
c sound "$(offload sound speech.wav 2>/dev/null)" '"label":"speech"'

# Transforming
if print -r -- "$D" | grep 'translate to en, installed' | grep -qw es; then
  offload translate --in $T/es.jsonl --out $T/t.out 2>/dev/null; c translate "$(cat $T/t.out)" 'hello\|world'
else s translate 'add Spanish in System Settings, General, Language & Region, Translation Languages'; fi
offload extract --in $T/en.jsonl --out $T/x.out 2>/dev/null; c extract "$(cat $T/x.out)" 'apple.com'
offload embed --in $T/en.jsonl --out $T/e.out 2>/dev/null; c embed "$(cat $T/e.out)" 'vector'
c embed-query "$(offload embed-query 'hello there' 2>/dev/null)" '='
if print -r -- "$D" | grep -q 'text model: available'; then
  offload generate --in $T/en.jsonl --out $T/g.out --instructions 'Summarise in one short sentence.' 2>/dev/null; c generate "$(cat $T/g.out)" '"text"'
  offload tag --in $T/en.jsonl --out $T/tg.out 2>/dev/null; c tag "$(cat $T/tg.out)" 'tags'
else s generate 'needs Apple Intelligence'; s tag 'needs Apple Intelligence'; fi

# Learning
for i in {0..29}; do
  print -r -- "{\"text\":\"chicken pasta recipe with garlic and butter number $i\",\"label\":\"food\"}"
  print -r -- "{\"text\":\"python code compiler and software bug number $i\",\"label\":\"dev\"}"
done > $T/tr.jsonl
M=$(offload train-text --in $T/tr.jsonl --out $T/m.mlmodelc 2>/dev/null); c train-output-is-json "$M" '^{.*training_accuracy.*}$'; c train-output-one-line "$(print -r -- "$M" | wc -l)" '^ *1$'; printf '{"id":"a","text":"a garlic butter pasta recipe"}\n' > $T/p.jsonl; offload predict --model $T/m.mlmodelc --in $T/p.jsonl --out $T/p.out 2>/dev/null; c train-predict "$(cat $T/p.out)" '"label":"food"'

# Setup and version
c doctor-report "$D" '^ready  *ocr'
M=$(offload setup --open nowhere 2>&1); c setup-bad-page "$?" '^2$'; c setup-bad-page-says "$M" 'intelligence or translation'
M=$(offload setup </dev/null 2>&1); R=$?; c setup-no-terminal-exit "$R" '^0$'; c setup-no-terminal-explains "$M" 'setup --yes'
M=$(offload setup --yes </dev/null 2>&1); R=$?; c setup-yes-exit "$R" '^0$'; c setup-yes-reports "$M" '^\(ready\|missing\)  *transcribe'
cat > $T/answer.exp <<EOF
set timeout 180
spawn "$O" setup --locale en-US
expect {
  -re {\[Y/n\] \$} { send "n\r"; exp_continue }
  -re {translate from} { send "es\r"; exp_continue }
  -re {press Return\. $} { send "\r"; exp_continue }
  timeout { exit 124 }
  eof
}
exit [lindex [wait] 3]
EOF
M=$(expect -f $T/answer.exp 2>&1); R=$?; c setup-terminal-exit "$R" '^0$'; c setup-asks-languages "$M" 'translate from'; c setup-checks-language "$M" 'Spanish'
P=../../../.claude-plugin/plugin.json; [[ -f $P ]] && c version "$(grep '"version"' $P)" "\"$(offload version)\""

# Batch behaviour
offload look --ops barcode --out $T/r.out qr.png 2>/dev/null; offload look --ops barcode --out $T/r.out qr.png 2>/dev/null; c resume "$(wc -l < $T/r.out)" '^ *1$'
printf '{"id":1,"text":"visit https://apple.com"}\n' > $T/n.jsonl; offload extract --in $T/n.jsonl --out $T/n.out 2>/dev/null; c number-id "$(cat $T/n.out)" '"id":"1"'
printf '\n{"id":"ok","text":"fine"}\nnot json\n{"text":"no id"}\n' > $T/b.jsonl; M=$(offload extract --in $T/b.jsonl --out $T/b.out 2>&1); R=$?; c bad-rows-exit "$R" '^1$'; c bad-rows-named "$M" 'skipped 2 '; c bad-rows-kept "$(cat $T/b.out)" '"id":"ok"'

# Usage mistakes exit 2, runtime failures exit 1, and nothing crashes
offload look --ops barcodes qr.png >/dev/null 2>&1; c bad-op "$?" '^2$'
offload look --ops '' qr.png >/dev/null 2>&1; c empty-ops "$?" '^2$'
offload similar --max-distance abc text.png >/dev/null 2>&1; c bad-distance "$?" '^2$'
offload similar --max-distance -1 text.png >/dev/null 2>&1; c negative-distance "$?" '^2$'
offload embed-query >/dev/null 2>&1; c embed-query-empty "$?" '^2$'
mkdir $T/keep; offload train-text --in $T/tr.jsonl --out $T/keep >/dev/null 2>&1; c train-refuses-folder "$?" '^2$'
offload train-text --in $T/nope.jsonl --out $T/z.mlmodelc >/dev/null 2>&1; c train-missing-input "$?" '^1$'
printf '{"text":"only one label","label":"a"}\n' > $T/one.jsonl; offload train-text --in $T/one.jsonl --out $T/one.mlmodelc >/dev/null 2>&1; c train-one-label "$?" '^2$'
: > $T/zero.jsonl; offload train-text --in $T/zero.jsonl --out $T/zero.mlmodelc >/dev/null 2>&1; c train-no-rows "$?" '^2$'
offload extract --in $T/nope.jsonl --out $T/no.out >/dev/null 2>&1; c row-missing-input "$?" '^1$'

# map, against a stand-in for Claude so it costs nothing
mkdir $T/stub $T/empty $T/home
cat > $T/stub/claude <<'EOF'
#!/bin/sh
/bin/cat > "$STUB_LOG"
case "$STUB_MODE" in
  limit) echo '{"is_error":true,"result":"You have hit your usage limit"}'; exit 1;;
  mixed) echo '{"total_cost_usd":0.01,"usage":{"output_tokens":5},"structured_output":{"items":[{"id":"r0","v":"a"},{"id":"r1","v":"b"},{"id":"r1","v":"c"},{"id":"r99","v":"x"}]}}';;
  all) items=$(/usr/bin/grep -o 'id="r[0-9]*"' "$STUB_LOG" | /usr/bin/sed 's/id="\(.*\)"/{"id":"\1","v":"ok"}/' | /usr/bin/paste -sd, -); echo "{\"structured_output\":{\"items\":[$items]}}";;
esac
EOF
chmod +x $T/stub/claude
print -r -- '{"properties":{"v":{"type":"string"}},"required":["v"]}' > $T/s.json
print -r -- '{"id":"Bob'"'"'s & co","text":"first"}' > $T/m.jsonl; print -r -- '{"id":"dup","text":"second"}' >> $T/m.jsonl; print -r -- '{"id":"gone","text":"third"}' >> $T/m.jsonl
M=$(PATH=$T/stub:$PATH STUB_MODE=mixed STUB_LOG=$T/log offload map --in $T/m.jsonl --out $T/m.out --system hi --schema $T/s.json 2>/dev/null); R=$?
c map-partial-exit "$R" '^1$'; c map-real-id "$(cat $T/m.out)" "Bob's & co"; c map-drops-repeats "$(wc -l < $T/m.out)" '^ *1$'; c map-stats "$M" '"missing":2'; c map-hides-ids "$(grep -c 'Bob' $T/log)" '^0$'
PATH=$T/stub:$PATH STUB_MODE=all STUB_LOG=$T/log offload map --in $T/m.jsonl --out $T/m.out --system hi --schema $T/s.json >/dev/null 2>&1; c map-resume-exit "$?" '^0$'; c map-resume-rows "$(wc -l < $T/m.out)" '^ *3$'
PATH=$T/stub:$PATH STUB_MODE=limit STUB_LOG=$T/log offload map --in $T/m.jsonl --out $T/l.out --system hi --schema $T/s.json >/dev/null 2>&1; c map-usage-limit "$?" '^75$'
PATH=$T/empty HOME=$T/home "$O" map --in $T/m.jsonl --out $T/x2.out --system hi --schema $T/s.json >/dev/null 2>&1; c map-no-claude "$?" '^1$'
offload map --in $T/m.jsonl --out $T/x3.out --system hi >/dev/null 2>&1; c map-needs-schema "$?" '^2$'

if [[ $1 == --live ]]; then
  print -r -- '{"id":"live one","text":"The capital of France is Paris."}' > $T/live.jsonl
  print -r -- '{"properties":{"city":{"type":"string"}},"required":["city"]}' > $T/city.json
  offload map --in $T/live.jsonl --out $T/live.out --system 'Name the city each item mentions.' --schema $T/city.json >/dev/null 2>$T/live.err; c live-map "$(cat $T/live.out)" 'Paris'
fi

rm -rf $T; echo "failures: $F, skipped: $K"; exit $F
