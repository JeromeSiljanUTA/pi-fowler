# pi-fowler

| ![Special Agent William Fowler](agent-fowler.jpg) | ![Agent Fowler in action](agent-fowler-topgun.jpg) |
|:--:|:--:|
| Special Agent William "Bill" Fowler | Fowler tangling with Decepticons |

<sub>Screenshots from *Transformers: Prime*.</sub>

A Nix flake that packages the **pi coding agent** (latest unstable) with a
**self-hosted Firecrawl extension** baked in, wired to the Firecrawl + SearXNG
stack in `shockwaves-lab/searxng-firecrawl`. No Firecrawl API key is required.

## What it ships

| Output | Description |
|---|---|
| `packages.<system>.default` | `pi-fowler` — pi with all extensions loaded on every run |
| `packages.<system>.pi-fowler` | The wrapped pi binary |
| `packages.<system>.pi-firecrawl` | The Firecrawl extension package on its own |
| `packages.<system>.pi-subagents` | `pi-subagents` 0.88.1 on its own |
| `packages.<system>.pi-parallel-sessions` | `pi-parallel-sessions` 0.2.8 on its own |

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
  - the three extensions are linked into `agent/nix/packages/` and loaded both
    from `agent/settings.json` and with `--extension` (pi canonicalizes the
    links, so each extension loads once);
  - `FIRECRAWL_API_URL` defaults to the self-hosted instance (an explicitly
    exported value is respected);
  - `safe.directory=*` is exported via `GIT_CONFIG_*`, so git trusts the
    repos on the shared `/workspace` mount that are owned by another uid
    instead of failing with "dubious ownership".
- `pi-subagents` is built with `pkgs.buildNpmPackage` from the pinned
  dependency tree in `nix/pi-subagents/` (a lockfile plus its `npmDepsHash`),
  so its runtime dependencies are resolved at build time rather than by
  `npm install` at launch.
- `pi-parallel-sessions` has no runtime dependencies, so its published tarball
  is fetched and unpacked with a pinned hash. It adds the `/sessions` switcher
  and Ctrl-R. The build drops its risky-command guard, which confirmed every
  `sudo` / `rm -rf` bash command through `ctx.ui.confirm`: sessions without an
  attached UI auto-deny that prompt, and inline ones stall until someone
  answers, so runs stranded instead of being protected.
- Because every extension comes from the flake, `agent/settings.json` declares
  no `npm:` packages and pi never touches the npm registry on startup.
- The extensions are declared as packages in `agent/settings.json`, not only on
  the wrapper's command line, because sessions that pi creates itself build
  their own resource loader from the agent directory: the `/sessions`
  switcher's new sessions and `pi-subagents` background runners never see the
  parent's argv. Without the package declarations those sessions started
  without the extensions, the skills, and the prompts.

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

The agent's config and memory live with a pi-fowler checkout instead of
`~/.pi/agent`:

```
agent/
├── settings.json     # default provider/model, theme, packages, other settings
├── keybindings.json  # key remaps that keep extensions from shadowing built-ins
├── AGENTS.md         # persistent memory and instructions
└── nix/packages/     # wrapper-managed links to the flake's extension packages
```

The wrapper looks for a pi-fowler checkout in this order:

1. `PI_FOWLER_AGENT_DIR`, if set.
2. `$PWD`, `$PWD/pi-fowler`.
3. Every ancestor of `$PWD`.
4. `/workspace/pi-fowler` (the persistent HARBINGER workspace share).
5. `~/pi-fowler`.
6. `~/pi-fowler/agent` as a fallback, seeded from the files packaged by the
   flake.

When it finds a checkout, `PI_CODING_AGENT_DIR` points at that checkout's
`agent/` directory. That means launching pi from anywhere in HARBINGER still
uses `/workspace/pi-fowler/agent`: settings persist across VM restarts and
changes show up in `git status` in the pi-fowler checkout for you to commit and
push.

`pi-parallel-sessions` binds `ctrl+r` to its `/sessions` switcher, but pi 1.5
binds `ctrl+r` to the built-in session rename, so startup reported an
"Extension shortcut conflict". Rather than patch the third-party package,
`keybindings.json` moves `app.session.rename` to `ctrl+shift+r`; the extension
keeps its documented `ctrl+r` and both work.

`settings.json`, `keybindings.json`, and `AGENTS.md` are tracked;
`agent/nix/` is rebuilt by the wrapper on every launch, so the links always
point at the store paths of the pi that is running. Credentials, model cache,
sessions, logs, and the runtime state written by `pi-subagents` are listed in
`.gitignore`, so `agent/auth.json`, `agent/mcp-auth.json`,
`agent/models-store.json`, `agent/sessions/`, `agent/missions/`,
`agent/pi-subagents/`, and `agent/*.log` are never committed. In particular,
the OpenRouter key saved by `/login` stays in the ignored `agent/auth.json` on
the persistent workspace, not in git.

Point somewhere else with `PI_FOWLER_AGENT_DIR`:

```bash
export PI_FOWLER_AGENT_DIR="$HOME/git/pi-fowler/agent"
```

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
