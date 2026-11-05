# Changelog

## 0.1.0 (unreleased)

First version: batch commands for Vision, Speech, Translation, NaturalLanguage, Create ML and Foundation Models; a Claude Code skill and plugin; a Claude batch runner; a self-test, Swift Testing tests and a synthetic benchmark. Builds in Swift 6 language mode.

A fresh install now needs only macOS 27 and Claude Code: the program, self-test and test files ship inside the skill, `install.sh` needs only `curl`, and `offload setup` walks you through each missing piece, opening System Settings where Apple requires it. `offload doctor` lists every dependency as ready or missing, and commands that hit a missing one say how to fix it. `offload map` replaces `claude_map.py`, so Python is no longer needed, and it no longer depends on ids surviving the model. Numeric ids work, unreadable rows are reported, bad options exit 2, training logs no longer mix with its JSON, and a failed `train-text` no longer crashes.
