# Command reference

Run `offload` for a summary and `offload doctor` to see which models are ready. If `offload` isn't on your `PATH`, use `~/.claude/skills/offload/bin/offload`. For worked examples, see [Getting started](getting-started.md).

Commands fall into two kinds:

- **Path commands** (`ocr`, `look`, `similar`, `doc`, `transcribe`, `sound`) read paths from arguments or stdin, one per line.
- **Row commands** (`translate`, `extract`, `embed`, `generate`, `tag`, `predict`, `map`) read a JSONL file.

```sh
find ~/Screenshots -name '*.png' | offload ocr --out text.jsonl --jobs 4
```

## Resuming

Give a batch command `--out file`, and it appends one JSON line per item. A rerun skips items that finished, and retries items that failed. `similar` and `doc` print to stdout and don't resume.

Resuming goes by path or id alone. If you change settings such as `--to`, `--ops` or `--instructions`, start a new output file, or the rerun keeps the old results.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Everything finished |
| 1 | Something failed. Failed items are marked with `error` and a rerun retries them. Rows with bad JSON or no id are counted on stderr, because they have no id to mark |
| 2 | A usage mistake, such as an unknown option or a bad number |
| 75 | `map` only: you reached a usage limit. Rerun later and it carries on |

## Row options

| Option | Default | Meaning |
|---|---|---|
| `--in`, `--out` | required | Input and output JSONL |
| `--id` | `id` | Field holding a row's identifier, a string or a number |
| `--text` | `text` | Field holding the text |
| `--max-chars` | 9000 | Trims longer text |
| `--limit` | none | Stops after this many new rows |

## Reading

### `ocr`
Text from images. `--jobs` sets parallel images, default 4. `--unique` drops repeated lines within an image, which helps with video contact sheets. Leave it off for receipts and tables, where repeats are real data. Output: `{"path", "lines"}`.

### `look`
`--ops` takes any of `barcode`, `classify`, `quality`, `faces`, `people`, `animals`. It runs all of them by default, and `--ops barcode` is much faster when that's all you need. `--jobs` sets parallel images, default 4.

### `similar`
Prints pairs of images within `--max-distance`, a number of 0 or more that defaults to 0.25, and exits 1 if any image couldn't be read. It compares every pair, so keep it under about 5,000 images.

### `doc`
PDFs and images to `{"page", "text", "tables", "lists"}`, one line per page as it goes. Unreadable files and pages get an `error` line. Check tables that matter: merged cells leave blanks.

### `transcribe`
Speech to text. `--locale` defaults to `en-US`. A missing language downloads on first use.

### `sound`
Sound labels with scores per file. Speech and music held up in testing, and other labels gave false alarms.

## Transforming

### `translate`
Detects each row's language and translates into `--to`, default `en`. English rows pass through. Only installed languages work, and a row in any other language gets a `not_installed` error naming what to add in System Settings, under General, Language & Region, Translation Languages. Apple doesn't let a command-line tool download these. `offload doctor --to en` lists languages installed for that target.

### `extract`
Links, dates, phone numbers, addresses, names, language and sentiment.

### `embed`
Meaning vectors as base64 float32. `offload embed-query "words"` gives one for a search. Combine these with keyword search, because they missed on some of our test searches.

### `generate`
Sends each row to Apple's on-device model with `--instructions "..."` or `--instructions @file`, and returns plain text. `--instructions` is required. Text too long for the on-device context gets trimmed using the token count Apple's error reports, then retried. It uses Apple's permissive setting unless you pass `--default-guardrails`. If the on-device model isn't ready, it stops before starting and says why.

### `tag`
Short topic tags per row. Pass `--default-guardrails` for Apple's stricter setting.

## Learning

### `train-text`
Input rows are `{"text", "label"}`, and malformed rows are skipped with a warning. You need at least two labels. `--out` must end in `.mlmodelc`, because it replaces that path. The command prints the model's accuracy as one JSON line on stdout, and training logs go to stderr.

```sh
offload train-text --in labelled.jsonl --out topics.mlmodelc
offload predict --model topics.mlmodelc --in new.jsonl --out labels.jsonl
```

Keep some labels out of training and compare them with the predictions before you rely on the model.

## Sending to Claude

### `map`
Runs a Claude model over JSONL rows through Claude Code, in batches, with tools, settings and saved sessions switched off. It needs Claude Code, and draws on your allowance or API balance.

```sh
offload map --in rows.jsonl --out results.jsonl --system @prompt.txt --schema item.json
```

| Option | Default | Meaning |
|---|---|---|
| `--system` | required | The instructions, as text or `@file` |
| `--schema` | required | JSON Schema file for one result. An `id` field gets added for you |
| `--model` | `haiku` | Any model Claude Code accepts |
| `--batch` | 8 | Most rows in one call |
| `--max-batch-chars` | 30000 | Most text in one call |
| `--workers` | 3 | Calls at once |

It also takes the row options above. Each output line is your schema's fields plus the row's `id`. Don't name a field `error`, because resuming treats a row with that field as unfinished. It prints a JSON summary when it ends, and stops starting calls at a usage limit.

## Setup

### `doctor`
Lists what each command needs as `ready` or `missing`, with the fix for anything missing, then the details. It changes nothing. `--locale` picks the speech language to check, default `en-US`, and `--to` the translation target, default `en`.

### `setup`
Gets what's missing. In a terminal it asks before each step:

- It downloads the speech model for your audio's language, and the search model.
- If Apple Intelligence is off, it opens that page of System Settings and waits while you turn it on.
- It asks which languages you translate from, checks each, and opens Translation Languages if one needs downloading. Apple only lets System Settings download these.
- If Claude Code is missing, it offers to run Anthropic's installer.

It finishes with the same report as `doctor`. `--yes` downloads without asking and never opens System Settings, which suits scripts and Claude. `--languages "es fr"` and `--locale fr-FR` answer those questions up front. `--open intelligence` or `--open translation` opens one page and stops. Run by another program without `--yes`, it only reports, so it never waits for input.
