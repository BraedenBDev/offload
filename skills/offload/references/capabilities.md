# Capabilities and test results

Tested on 5 Nov 2026 on macOS 27.0.1 with an M1 Max and 32 GB. The test data was a private library of about 8,500 short social videos and posts. It can't ship, so `make bench` offers a smaller synthetic check you can run yourself.

These numbers come from one machine, and some samples are small. The classifier result rests on 25 human labels and the Haiku comparison on 16 posts. Treat them as a starting point and test on your own data.

## Use these

| Command | What it does | Measured | Limits |
|---|---|---|---|
| `ocr` | Text from images | 200 to 300 images a minute, with 4 jobs, on 1080 by 1446 contact sheets | Garbles small text and some Chinese |
| `look --ops barcode` | QR codes and barcodes | 13 to 50 images a second; decoded a link hidden in a video | Needs the code large enough in the image |
| `transcribe` | Speech to text | 288 s of audio in 6 s, against 41 s for whisper.cpp medium.en; 94 to 97% word agreement with Whisper | Can miss names ("Primer" for "Framer"); other languages download on first use |
| `translate` | Rows into English | Under 2 s a line; correct on Chinese and Spanish samples | Installed languages only; can misread short mixed text |
| `doc` | PDF or image to text, tables, lists | 13-page PDF in 6.5 s with 6 tables found | One receipt came back as a single column, and merged cells leave blanks; check tables that matter |
| `extract` | Links, dates, phones, addresses, names, sentiment | Milliseconds a row | Links, dates and phones held up; names can be wrong |
| `train-text`, `predict` | Train and run a text classifier | 7,576 rows in 17 s; under 1 ms a prediction; 20 of 25 on human labels, the same score as the API that supplied its training labels | Learns whatever labels you give it, mistakes included |
| `similar` | Near-duplicate images | 60 images in under 1 s | Compares every pair. The same image resized scored 0.22 and unrelated images 0.35 and up, so the margin is narrow |

## Use with care

| Command | Finding | Good for |
|---|---|---|
| `generate` | Free, about 5 s a row, plain text only. Against Haiku on 16 posts it kept 33 numbers to 52, dropped recipe steps and ignored the requested format | Rough gists, and data that must stay on the Mac |
| `tag` | About 2 s a row, sensible tags, occasional safety blocks | Extra search terms |
| `embed` | 0.03 s a row. Right on some searches, wrong on others, with scores bunched together | Meaning search combined with keyword search |
| `look --ops classify,quality,faces,people,animals` | Fast, broad labels | Filtering images |
| `sound` | Speech and music held up; false alarms such as gunfire on an ad | Detecting speech or music |

## Do not use

| Tool | Why |
|---|---|
| `NLEmbedding` sentence embeddings | Ranked a recipe closer than a matching sentence |
| The on-device model reading images | Invented a site name, named the wrong tool, misdescribed a build |
| The on-device model as a classifier | 14 of 25, against 20 for a trained classifier |
| Guided JSON from the on-device model | Safety filters blocked 9 of 24 harmless posts, and 3 of 5 with the permissive setting |
| `ImageCreator` image generation | Returned `notSupported` from a command-line tool |

## Not tested

Apple's `fm serve`, Parakeet, Core Spotlight search and handwriting. Vision pose, segmentation and saliency had no use case. Private Cloud Compute stays out of scope, because offload runs on your Mac only.

## Claude through claude_map.py

Haiku on 16 posts with 3 workers took 32 s, about 2 s a row. Claude Code reported about $0.0006 a row. On a subscription, that use draws on your allowance and doesn't bill by the call.

## Token savings

We haven't measured an end-to-end saving yet. A full run on the test library is in progress, and its result will go here.
