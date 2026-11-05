# Command reference

Run `offload` for a summary and `offload doctor` to see which models are ready.

Commands fall into two kinds:

- **Path commands** (`ocr`, `look`, `similar`, `transcribe`) read paths from arguments or stdin, one per line. `doc` and `sound` read paths from arguments only.
- **Row commands** (`translate`, `extract`, `embed`, `generate`, `tag`, `predict`) read a JSONL file.

```sh
find ~/Screenshots -name '*.png' | offload ocr --out text.jsonl --jobs 4
```

## Resuming

Give a batch command `--out file`, and it appends one JSON line per item. A rerun skips items that finished, and retries items that failed. `similar`, `doc` and `sound` print to stdout and don't resume.

## Row options

| Option | Default | Meaning |
|---|---|---|
| `--in`, `--out` | required | Input and output JSONL |
| `--id` | `id` | Field holding a row's identifier, which must be a string |
| `--text` | `text` | Field holding the text |
| `--max-chars` | 9000 | Trims longer text |
| `--limit` | none | Stops after this many new rows |

## Reading

### `ocr`
Text from images. `--jobs` sets parallel images, default 4. Output: `{"path", "lines"}`.

### `look`
`--ops` takes any of `barcode`, `classify`, `quality`, `faces`, `people`, `animals`. It runs all of them by default, and `--ops barcode` is much faster when that's all you need.

### `similar`
Prints pairs of images within `--max-distance`, default 0.25. It compares every pair, so keep it under about 5,000 images.

### `doc`
PDFs and images to `{"page", "text", "tables", "lists"}`, one line per page. Check tables that matter: merged cells leave blanks.

### `transcribe`
Speech to text. `--locale` defaults to `en-US`. A missing language downloads on first use.

### `sound`
Sound labels with scores per file. Speech and music held up in testing, and other labels gave false alarms.

## Transforming

### `translate`
Detects each row's language and translates into `--to`, default `en`. English rows pass through. `offload doctor` lists installed languages.

### `extract`
Links, dates, phone numbers, addresses, names, language and sentiment.

### `embed`
Meaning vectors as base64 float32. `offload embed-query "words"` gives one for a search. Combine these with keyword search, because they missed on some of our test searches.

### `generate`
Sends each row to Apple's on-device model with `--instructions "..."` or `--instructions @file`, and returns plain text. It halves text that exceeds the 4,096-token context and retries. It uses Apple's permissive setting unless you pass `--default-guardrails`.

### `tag`
Short topic tags per row.

## Learning

### `train-text`
Input rows are `{"text", "label"}`. Output is a compiled model folder, and the command prints its accuracy.

```sh
offload train-text --in labelled.jsonl --out topics.mlmodelc
offload predict --model topics.mlmodelc --in new.jsonl --out labels.jsonl
```

Keep some labels out of training and compare them with the predictions before you rely on the model.
