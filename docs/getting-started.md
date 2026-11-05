# Getting started

Install offload first, using the steps in the [README](../README.md#install). If anything is missing later, run `offload setup` in a terminal and it walks you through it. You can run these examples from any folder, and each one is safe to rerun. They use `jq`, which comes with macOS.

## Read text from a folder of images

```sh
find ~/Screenshots -name '*.png' | offload ocr --out text.jsonl
```

Each image becomes one line of JSON:

```json
{"path":"/Users/you/Screenshots/one.png","lines":["OFFLOAD TEST 2027"]}
```

Stop it whenever you like. Run the same command again and it carries on from where it stopped.

## Pull fields out of receipts with Haiku

Claude reads the text from OCR, so it never has to read the images.

**1. Read the images on your Mac.**

```sh
find ~/Receipts -name '*.png' | offload ocr --out text.jsonl
```

**2. Turn the results into rows.**

```sh
jq -c '{id: .path, text: (.lines | join("\n"))}' text.jsonl > rows.jsonl
```

**3. Say what you want back.** Save this as `receipt.json`:

```json
{
  "properties": {
    "merchant": {"type": "string"},
    "total": {"type": "string"}
  },
  "required": ["merchant", "total"]
}
```

**4. Try 25 rows and read the results.**

```sh
offload map \
  --in rows.jsonl --out receipts.jsonl --limit 25 \
  --system 'Find the merchant and total on each receipt. Use an empty string if one is missing.' \
  --schema receipt.json
```

**5. Run the rest.** Repeat the command without `--limit`. It skips the rows already done.

`offload map` uses Haiku by default, and `--model sonnet` changes that. On a Claude subscription, this draws on your allowance. With `ANTHROPIC_API_KEY` set, Claude Code may bill your API account instead.

## Transcribe audio, then sort it

**1. Transcribe.** Audio files such as `.wav` and `.m4a` work directly. For video, extract the audio first.

```sh
find ~/Calls -name '*.m4a' | offload transcribe --out calls.jsonl
```

**2. Make rows.**

```sh
jq -c '{id: .path, text: .text}' calls.jsonl > rows.jsonl
```

**3. Train a classifier.** You need some labelled examples, as JSONL with `text` and `label` fields, and several for each label:

```json
{"text":"I'd like to cancel my subscription","label":"support"}
{"text":"Can you send me a quote for 20 seats?","label":"sales"}
```

```sh
offload train-text --in labelled.jsonl --out topics.mlmodelc
```

**4. Sort everything.**

```sh
offload predict --model topics.mlmodelc --in rows.jsonl --out topics.jsonl
```

Each row comes back with a `label` and the scores for its top two labels. Check a sample by hand, and keep some labelled rows out of training so you can measure accuracy.

## If something goes wrong

| What you see | What to do |
|---|---|
| `offload: command not found` | Add `~/.local/bin` to your `PATH`, or run `~/.claude/skills/offload/bin/offload` |
| `offload` won't start | It needs macOS 27 on Apple Silicon. Check with `sw_vers` and `uname -m` |
| The command exits with code 1 | Some items failed. Search the output for `error`, then rerun to retry them |
| The command exits with code 2 | A usage mistake. The message says which option to fix |
| `skipped N rows with bad JSON or no id` | Those lines have no usable id or aren't valid JSON. Fix them and rerun |
| `transcribe` or `embed` can't get a model | Connect to the internet and run `offload setup` |
| `generate` or `tag` say the model is unavailable | Follow the message. It usually means turning on Apple Intelligence in System Settings. `offload doctor` shows the current state |
| `guardrail` errors from `generate` | Apple's safety filter blocked that row. Send those rows to Haiku |
| `translate` reports `not_installed` | Add the language it names in System Settings, under General, Language & Region, Translation Languages. `offload doctor` lists what's installed |
| A rerun keeps old results after you changed a setting | Resuming goes by path or id alone, so use a new output file |
| `offload map` exits with code 75 | You reached a usage limit. Rerun later and it carries on |
| `sound` returns nothing | The clip may be too short: a 2-second clip returned nothing in testing |

After a macOS update, run `~/.claude/skills/offload/scripts/selftest.sh` to check that everything still works.
