# pi-fowler

A Nix flake that packages the **pi coding agent** (latest unstable) with the
official **Firecrawl extension** baked in, so `pi` is ready to scrape, crawl,
map, search, and extract from the web out of the box.

## What it ships

| Output | Description |
|---|---|
| `packages.<system>.default` | `pi-fowler` — pi with the Firecrawl extension loaded on every run |
| `packages.<system>.pi-fowler` | The wrapped pi binary |
| `packages.<system>.pi-firecrawl` | The extension package on its own |

`overlays.default` exposes `pi-fowler` for use in NixOS / home-manager configs.

## How it works

- `pi-coding-agent` is taken from `nixpkgs/nixos-unstable`.
- `firecrawl/pi-firecrawl` is fetched from GitHub and installed with its
  runtime dependency (`@mendable/firecrawl-js`).
- The upstream `src/index.ts` entry point is relocated to
  `extensions/firecrawl.ts`, so pi lists the extension as `firecrawl.ts`
  rather than the unhelpful `src/index.ts`.
- The `pi` binary is wrapped to inject `--extension <pi-firecrawl>` on every
  invocation. This leaves your writable `~/.pi/agent` directory (settings,
  sessions, auth) untouched, unlike overriding `PI_CODING_AGENT_DIR`.

## Usage

Run it directly:

```bash
nix run git+ssh://git@your-git-server/pi-fowler
```

Build / install it:

```bash
nix build git+ssh://git@your-git-server/pi-fowler
```

As a flake input in a NixOS / home-manager config:

```nix
{
  inputs.pi-fowler.url = "git+ssh://git@your-git-server/pi-fowler";

  # home-manager
  home.packages = [ inputs.pi-fowler.packages.${pkgs.system}.default ];

  # or via the overlay
  # nixpkgs.overlays = [ inputs.pi-fowler.overlays.default ];
  # home.packages = [ pkgs.pi-fowler ];
}
```

## Configuration

The extension reads these environment variables at runtime:

| Variable | Default | Purpose |
|---|---|---|
| `FIRECRAWL_API_KEY` | _(required by the extension)_ | Firecrawl API key. |
| `FIRECRAWL_API_URL` | `https://api.firecrawl.dev` | Point at a self-hosted Firecrawl instance. |
| `FIRECRAWL_TIMEOUT_MS` | SDK default | Per-request timeout. |
| `FIRECRAWL_MAX_RETRIES` | SDK default | Retry budget. |

For a self-hosted instance (e.g. the `searxng-firecrawl` stack in
`shockwaves-lab`):

```bash
export FIRECRAWL_API_URL=http://firecrawl.nemesis.home.arpa
export FIRECRAWL_API_KEY=dummy   # self-hosted with USE_DB_AUTHENTICATION=false
```

Then run `pi` and use tools like `firecrawl_scrape` and `firecrawl_search`.
Inside a session, `/firecrawl` reports the configured API URL and whether a key
is present.

## Updating the packed extension

Bump the `rev` and both hashes in `flake.nix`:

```bash
nix-prefetch-github firecrawl pi-firecrawl --rev <new-rev>
# update rev + hash, then:
nix build .#pi-firecrawl   # -> prints the new npmDepsHash on mismatch
```
