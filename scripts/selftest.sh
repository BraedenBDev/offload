#!/bin/zsh
# Checks that every offload command still runs. Run it after a macOS update. The exit code is the number of failures.
cd "${0:A:h}/../tests/fixtures" || exit 99
T=$(mktemp -d); F=0
c() { if echo "$2" | grep -qi -- "$3"; then echo "PASS $1"; else echo "FAIL $1"; F=$((F+1)); fi; }
printf '{"id":"a","text":"Hola mundo, esto es una prueba de la herramienta"}\n' > $T/es.jsonl
printf '{"id":"a","text":"Tim Cook visited https://apple.com on March 3 2027"}\n' > $T/en.jsonl
c ocr "$(offload ocr text.png 2>/dev/null)" 'OFFLOAD TEST'
c barcode "$(offload look --ops barcode qr.png 2>/dev/null)" 'example.com/offload'
c similar "$(offload similar --max-distance 5 text.png qr.png 2>/dev/null)" 'distance'
c doc "$(offload doc text.png 2>/dev/null)" 'OFFLOAD'
c transcribe "$(offload transcribe speech.wav 2>/dev/null)" 'speech test'
c sound "$(offload sound speech.wav 2>/dev/null)" 'speech'
offload translate --in $T/es.jsonl --out $T/t.out 2>/dev/null; c translate "$(cat $T/t.out)" 'hello\|world'
offload extract --in $T/en.jsonl --out $T/x.out 2>/dev/null; c extract "$(cat $T/x.out)" 'apple.com'
offload embed --in $T/en.jsonl --out $T/e.out 2>/dev/null; c embed "$(cat $T/e.out)" 'vector'
offload generate --in $T/en.jsonl --out $T/g.out --instructions 'Summarise in one short sentence.' 2>/dev/null; c generate "$(cat $T/g.out)" '"text"'
offload tag --in $T/en.jsonl --out $T/tg.out 2>/dev/null; c tag "$(cat $T/tg.out)" 'tags'
python3 -I -c "
import json
for i in range(30):
    print(json.dumps({'text':f'chicken pasta recipe with garlic and butter number {i}','label':'food'}))
    print(json.dumps({'text':f'python code compiler and software bug number {i}','label':'dev'}))" > $T/tr.jsonl
offload train-text --in $T/tr.jsonl --out $T/m.mlmodelc >/dev/null 2>&1; printf '{"id":"a","text":"a garlic butter pasta recipe"}\n' > $T/p.jsonl; offload predict --model $T/m.mlmodelc --in $T/p.jsonl --out $T/p.out 2>/dev/null; c train-predict "$(cat $T/p.out)" '"label":"food"'
rm -rf $T; echo "failures: $F"; exit $F
