# Contributing

The most useful contribution today is a test report from a Mac other than an M1 Max.

## Setup

```sh
git clone https://github.com/BraedenBDev/offload && cd offload
make test
```

Using offload needs nothing but macOS and Claude Code. Working on it needs Xcode 27.

To report results, you only need the self-test: `~/.claude/skills/offload/scripts/selftest.sh`.

## Changes

- Add a command only after testing it on real data, and record the result in `skills/offload/references/capabilities.md`, including failures.
- Keep commands resumable where they process many items.
- Add a check to `skills/offload/scripts/selftest.sh` for each new command, and a Swift Testing test in `tests/offloadTests` for shared logic.
- Use public or synthetic files in tests. Keep private data out of the repo, including in screenshots and benchmark output.
- Run `make bundle` before committing a change to `Sources`, because the skill ships that binary and CI fails if it's out of date.
- Run `make virgin` when you change anything about installing. It installs into a sandbox with developer tools, Homebrew and your config blocked. Nothing a user needs may depend on those.
- Bump `version` in `.claude-plugin/plugin.json` and `Sources/offload/Offload.swift` for each release, because plugin users receive updates only when it changes.
- Run `claude plugin validate --strict .` before a pull request.
- Edit artwork in `docs/assets/src/art.html` and rebuild it with `docs/assets/src/render.sh`.
