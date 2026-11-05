# Security

## Report a problem

Use [GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-security-vulnerabilities/privately-reporting-a-security-vulnerability) on this repository. Please don't open a public issue for a security bug.

## What leaves your Mac

`offload` commands make no network calls of their own. Apple's frameworks can download language and model assets, for example when `transcribe` first meets a language.

`offload map` sends your rows to Anthropic through Claude Code.

## The bundled program

The skill ships a prebuilt program at `skills/offload/bin/offload`, so a fresh install doesn't need developer tools. It links only to macOS's own system libraries. It carries an ad-hoc signature and isn't notarized by Apple. `install.sh` fetches it with `curl`, which doesn't mark it as quarantined; a copy downloaded through a browser would be blocked by Gatekeeper.

`skills/offload/bin/SOURCE_SHA256` records the source that `make bundle` last built, and CI fails if the two drift apart. That catches a stale program, and doesn't prove who built it. If you'd rather not run a prebuilt program, read the source and run `make bundle` yourself with Xcode 27.

## Untrusted content

Images, audio and web text can contain instructions written for an AI. offload treats them as data:

- `offload map` runs models with no tools, no settings and no saved session.
- It wraps each row in tags with an unguessable name, and tells the model not to follow instructions inside them.
- The model only sees position keys for rows, so it can't alter an id or invent a row.

These steps reduce the risk and don't remove it. Never run commands, links or code that extraction returns without reading them first.
