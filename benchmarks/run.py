#!/usr/bin/env python3
"""Synthetic speed and sanity check. Prints a Markdown table. Uses `say` and the test fixtures, so anyone can run it.

Synthetic speech and clean images are easy cases, so read these as speed numbers, not real-world accuracy."""
import difflib, json, os, re, shutil, subprocess, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "tests", "fixtures")
SENTENCES = [
    "The quick brown fox jumps over the lazy dog near the river bank.",
    "Please send the quarterly report to the finance team before Friday afternoon.",
    "Add two tablespoons of olive oil to the pan and cook the garlic for one minute.",
    "The train to Barcelona leaves from platform four at half past nine.",
    "Install the package, restart the server, then check the logs for errors.",
    "Three sets of ten squats will warm up your legs before the main workout.",
    "The museum opens at ten and closes early on public holidays.",
    "Our new model reads the document and returns a short summary in plain English.",
]
words = lambda s: re.findall(r"[a-z0-9']+", s.lower())


def timed(cmd, **kw):
    t = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, **kw)
    return time.time() - t, p


with tempfile.TemporaryDirectory() as d:
    rows = []
    imgs = []
    for i in range(100):
        p = os.path.join(d, f"t{i}.png")
        shutil.copy(os.path.join(FIX, "text.png"), p)
        imgs.append(p)
    s, p = timed(["offload", "ocr", "--jobs", "4", *imgs])
    ok = sum("OFFLOAD TEST 2027" in l for l in p.stdout.splitlines())
    rows.append(("ocr", "100 images, 4 jobs", f"{s:.1f} s", f"{ok}/100 exact"))

    qrs = []
    for i in range(100):
        p = os.path.join(d, f"q{i}.png")
        shutil.copy(os.path.join(FIX, "qr.png"), p)
        qrs.append(p)
    s, p = timed(["offload", "look", "--ops", "barcode", *qrs])
    ok = sum("example.com/offload" in l for l in p.stdout.splitlines())
    rows.append(("look --ops barcode", "100 images", f"{s:.1f} s", f"{ok}/100 decoded"))

    wavs, audio = [], 0.0
    for i, t in enumerate(SENTENCES):
        p = os.path.join(d, f"s{i}.wav")
        subprocess.run(["say", "-o", p, "--data-format=LEI16@16000", t], check=True)
        wavs.append(p)
        audio += os.path.getsize(p) / 32000
    s, p = timed(["offload", "transcribe", *wavs])
    res = [json.loads(l) for l in p.stdout.splitlines()]
    sim = [difflib.SequenceMatcher(None, words(r.get("text", "")), words(t)).ratio() for r, t in zip(res, SENTENCES)]
    rows.append(("transcribe", f"{audio:.0f} s of speech", f"{s:.1f} s", f"{100 * sum(sim) / len(sim):.0f}% word match"))

    rowsfile = os.path.join(d, "es.jsonl")
    with open(rowsfile, "w") as f:
        for i in range(20):
            f.write(json.dumps({"id": str(i), "text": f"Hola, esta es la prueba numero {i} de la herramienta."}) + "\n")
    s, _ = timed(["offload", "translate", "--in", rowsfile, "--out", rowsfile + ".out"])
    n = sum("text" in json.loads(l) for l in open(rowsfile + ".out"))
    rows.append(("translate", "20 Spanish lines", f"{s:.1f} s", f"{n}/20 translated"))

    train = os.path.join(d, "train.jsonl")
    with open(train, "w") as f:
        for i in range(500):
            f.write(json.dumps({"text": f"chicken pasta recipe with garlic and butter {i}", "label": "food"}) + "\n")
            f.write(json.dumps({"text": f"python compiler bug in the software build {i}", "label": "dev"}) + "\n")
    s, _ = timed(["offload", "train-text", "--in", train, "--out", os.path.join(d, "m.mlmodelc")])
    rows.append(("train-text", "1,000 rows", f"{s:.1f} s", "see make test"))

print("| Command | Workload | Time | Result |\n|---|---|---|---|")
for r in rows:
    print("| " + " | ".join(r) + " |")
