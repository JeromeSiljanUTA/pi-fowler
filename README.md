# pi-fowler

A Nix flake that packages the **pi coding agent** (latest unstable) with a
**self-hosted Firecrawl extension** baked in, wired to the Firecrawl + SearXNG
stack in `shockwaves-lab/searxng-firecrawl`. No Firecrawl API key is required.

## What it ships

| Output | Description |
|---|---|
| `packages.<system>.default` | `pi-fowler` — pi with the Firecrawl extension loaded on every run |
| `packages.<system>.pi-fowler` | The wrapped pi binary |
| `packages.<system>.pi-firecrawl` | The extension package on its own |

`overlays.default` exposes `pi-fowler` for use in NixOS / home-manager configs.

## How it works

- `pi-coding-agent` is taken from `nixpkgs/nixos-unstable`.
- The Firecrawl extension is vendored at `extensions/firecrawl.ts` (synced
  from `shockwaves-lab/searxng-firecrawl/firecrawl.pi-extension.ts`). It talks
  to the self-hosted Firecrawl HTTP API with `fetch`, uses only pi's bundled
  peer dependencies, and therefore has no npm runtime dependencies — it is
  installed as a plain pi package instead of via `npm`.
- The extension registers `firecrawl_scrape` and `firecrawl_search`. Search is
  backed by SearXNG in the `searxng-firecrawl` stack.
- The `pi` binary is wrapped so that:
  - `PI_CODING_AGENT_DIR` points at a version-controlled `agent/` directory
    instead of `~/.pi/agent`;
  - `--extension <pi-firecrawl>` is injected on every invocation;
  - `FIRECRAWL_API_URL` defaults to the self-hosted instance (an explicitly
    exported value is respected).

## Usage

Run it directly:

```bash
nix run http://git.nemesis.home.arpa/jerome/pi-fowler
```

Build / install it:

```bash
nix build http://git.nemesis.home.arpa/jerome/pi-fowler
```

As a flake input in a NixOS / home-manager config:

```nix
{
  inputs.pi-fowler.url = "http://git.nemesis.home.arpa/jerome/pi-fowler";

  # home-manager
  home.packages = [ inputs.pi-fowler.packages.${pkgs.system}.default ];

  # or via the overlay
  # nixpkgs.overlays = [ inputs.pi-fowler.overlays.default ];
  # home.packages = [ pkgs.pi-fowler ];
}
```

## Version-controlled configuration

The agent's config and memory live with the pi-fowler checkout instead of
`~/.pi/agent`:

```
agent/
├── settings.json   # default provider/model, theme, and other settings
└── AGENTS.md       # persistent memory and instructions
```

`PI_CODING_AGENT_DIR` is set to `$HOME/pi-fowler/agent`, so clone the repo to
`~/pi-fowler` and pi reads and writes its config there. Anything pi changes
shows up in `git status` for you to commit and push.

Point somewhere else with `PI_FOWLER_AGENT_DIR`:

```bash
export PI_FOWLER_AGENT_DIR="$HOME/git/pi-fowler/agent"
```

Credentials, model cache, sessions, and logs are listed in `.gitignore`, so
`agent/auth.json`, `agent/models-store.json`, `agent/sessions/`, and
`agent/*.log` are never committed.

## Firecrawl configuration

| Variable | Default | Purpose |
|---|---|---|
| `FIRECRAWL_API_URL` | `http://firecrawl.nemesis.home.arpa` | Base URL of the self-hosted Firecrawl API. Set by the wrapper unless already exported. |
| `FIRECRAWL_API_KEY` | _(unused)_ | Not required — the stack runs with `USE_DB_AUTHENTICATION=false`. |

The default target is the Firecrawl instance from
`shockwaves-lab/searxng-firecrawl`, which also provides SearXNG for
`firecrawl_search`. Point it somewhere else at runtime:

```bash
export FIRECRAWL_API_URL=http://localhost:3002
pi
```

Then use the `firecrawl_scrape` and `firecrawl_search` tools inside a session.

## Updating the vendored extension

The source of truth for the extension is
`shockwaves-lab/searxng-firecrawl/firecrawl.pi-extension.ts`. To sync a change,
copy it over (keeping the self-hosted default URL) and rebuild:

```bash
cp /path/to/searxng-firecrawl/firecrawl.pi-extension.ts extensions/firecrawl.ts
nix build .#pi-firecrawl
```
