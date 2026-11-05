# Security

## Report a problem

Use [GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-security-vulnerabilities/privately-reporting-a-security-vulnerability) on this repository. Please don't open a public issue for a security bug.

## What leaves your Mac

`offload` commands make no network calls of their own. Apple's frameworks can download language and model assets, for example when `transcribe` first meets a language.

`claude_map.py` sends your rows to Anthropic through Claude Code.

## Untrusted content

Images, audio and web text can contain instructions written for an AI. offload treats them as data:

- `claude_map.py` runs models with no tools, no settings and no saved session.
- It wraps each row in tags and tells the model not to follow instructions inside them.

These steps reduce the risk and don't remove it. Never run commands, links or code that extraction returns without reading them first.
