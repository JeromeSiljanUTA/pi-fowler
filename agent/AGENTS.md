# pi-fowler memory

Persistent instructions and notes for pi live in this file so they are version
controlled alongside the flake. When pi is asked to remember something, it
appends here instead of writing to `~/.pi/agent/AGENTS.md`.

<!-- Add durable preferences, conventions, and facts below. -->

## Preferences

- Be brief with responses in general. More detail will be requested when needed.
- In all code, do not write comments that explain *what* the code is doing. Only write comments that explain *why* a decision was made. Answering "why" questions is fine.
- pi usually will not have push access. When asked to commit, just commit; do not attempt to figure out how to push.

## teletraan (LG TV)

- Custom-home source: `/workspace/webos-custom-home`; TV docs/scripts: `/workspace/teletraan`.
- "Deploy/push the code" to the TV = run `/workspace/teletraan/scripts/deploy-customhome.sh` (SSH `root@192.168.10.30`, password `alpine`). Recipe and gotchas are in `teletraan/README.md` → "Deploying to the TV".
