# Contributing

The most useful contribution today is a test report from a Mac other than an M1 Max.

## Setup

```sh
git clone https://github.com/BraedenBDev/offload && cd offload
make test
```

## Changes

- Add a command only after testing it on real data, and record the result in `skills/offload/references/capabilities.md`, including failures.
- Keep commands resumable where they process many items.
- Add a check to `scripts/selftest.sh` for each new command, and a Swift Testing test in `tests/offloadTests` for shared logic.
- Use public or synthetic files in tests. Keep private data out of the repo, including in screenshots and benchmark output.
- Bump `version` in `.claude-plugin/plugin.json` and `Sources/offload/Offload.swift` for each release, because plugin users receive updates only when it changes.
- Run `claude plugin validate --strict .` before a pull request.
- Edit artwork in `docs/assets/src/art.html` and rebuild it with `docs/assets/src/render.sh`.
