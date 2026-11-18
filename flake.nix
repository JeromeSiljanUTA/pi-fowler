{
  description = "pi-fowler — pi coding agent with a self-hosted Firecrawl extension baked in";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f {
          inherit system;
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        });

    # Self-hosted Firecrawl from shockwaves-lab/searxng-firecrawl.
    # No Firecrawl API key is needed (USE_DB_AUTHENTICATION=false).
    # Override at runtime with FIRECRAWL_API_URL.
    firecrawlUrl = "http://firecrawl.nemesis.home.arpa";
  in {
    packages = forAllSystems ({pkgs, ...}: let
      # Vendored extension. It has no npm runtime dependencies (it talks to
      # the Firecrawl HTTP API with fetch and uses pi's bundled peer deps),
      # so it is installed as a plain pi package rather than via npm.
      pi-firecrawl =
        pkgs.runCommand "pi-firecrawl-0.2.0" {
          meta = {
            description = "Firecrawl extension for pi backed by a self-hosted Firecrawl + SearXNG stack";
            homepage = "https://github.com/firecrawl/pi-firecrawl";
            license = pkgs.lib.licenses.mit;
          };
        } ''
          mkdir -p $out/lib/node_modules/pi-firecrawl/extensions
          cp ${./extensions/firecrawl.ts} $out/lib/node_modules/pi-firecrawl/extensions/firecrawl.ts

          cat > $out/lib/node_modules/pi-firecrawl/package.json <<'JSON'
          {
            "name": "pi-firecrawl",
            "version": "0.2.0",
            "type": "module",
            "keywords": ["pi-package"],
            "pi": { "extensions": ["./extensions"] }
          }
          JSON
        '';

      # Built from the pinned dependency tree in nix/pi-subagents. Its bundle
      # imports its runtime deps (yaml, jiti, ...) with bare specifiers, so the
      # dependency tree is installed next to the package in lib/node_modules
      # instead of inside it.
      pi-subagents = pkgs.buildNpmPackage {
        pname = "pi-subagents";
        version = "0.88.1";
        src = ./nix/pi-subagents;
        npmDepsHash = "sha256-/dZ+iR6bFVpIxCbf1wVhkS32jyij+LUpIhPHhOMNHNk=";
        dontNpmBuild = true;

        installPhase = ''
          mkdir -p $out/lib/node_modules
          cp -r node_modules/. $out/lib/node_modules/
        '';

        meta = {
          description = "Single-agent delegation and scripted multi-agent workflows for pi";
          homepage = "https://github.com/nicobailon/pi-subagents";
          license = pkgs.lib.licenses.mit;
        };
      };

      # Has no runtime dependencies, and its non-optional peer dependencies
      # would pull the whole pi package tree into node_modules, so this takes
      # the published tarball rather than an npm dependency tree.
      pi-parallel-sessions =
        pkgs.runCommand "pi-parallel-sessions-0.2.8" {
          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/pi-parallel-sessions/-/pi-parallel-sessions-0.2.8.tgz";
            hash = "sha512-w5YIKcWVJIdMs972Xrc0EumNKlB5d4eTs+vuYqYAlfiZjkeBjFb4Iom5XCFOqkxx2EQOmnCVjdLJXaGfkHikfg==";
          };
          meta = {
            description = "Run multiple live sessions in parallel in pi";
            homepage = "https://github.com/liushihao456/pi-sessions";
            license = pkgs.lib.licenses.mit;
          };
        } ''
          mkdir -p $out/lib/node_modules/pi-parallel-sessions
          tar -xzf $src --strip-components=1 -C $out/lib/node_modules/pi-parallel-sessions

          # 0.2.8 asks for confirmation before every sudo / rm -rf bash command.
          # Its child sessions have no UI attached, so the confirm resolves to
          # "denied", and inline prompts hold a run until answered; that strands
          # work instead of protecting it. Pi's own approval flow still applies.
          substituteInPlace $out/lib/node_modules/pi-parallel-sessions/index.ts \
            --replace-fail 'return `Dangerous bash command in ''${sessionName}: ''${command}`;' 'return null;'
        '';

      # Default files seeded into a brand-new agent directory. Existing files
      # are never overwritten, so user changes survive upgrades.
      pi-fowler-agent-defaults = pkgs.runCommand "pi-fowler-agent-defaults" {} ''
        mkdir -p $out
        cp ${./agent/AGENTS.md} $out/AGENTS.md
        cp ${./agent/settings.json} $out/settings.json
        cp ${./agent/keybindings.json} $out/keybindings.json
      '';

      pi-fowler = pkgs.writeShellApplication {
        name = "pi";
        runtimeInputs = [pkgs.nodejs pkgs.coreutils pkgs.gnugrep];
        text = ''
          is_pi_fowler_checkout() {
            [ -f "$1/flake.nix" ] &&
              [ -d "$1/agent" ] &&
              grep -q 'pi-fowler' "$1/flake.nix"
          }

          find_checkout() {
            local candidate
            for candidate in \
              "$PWD" \
              "$PWD/pi-fowler" \
              "/workspace/pi-fowler" \
              "$HOME/pi-fowler"; do
              if is_pi_fowler_checkout "$candidate"; then
                printf '%s\n' "$candidate"
                return 0
              fi
            done
            # Walking up keeps deep working directories on the same agent
            # directory instead of falling back to an empty seeded one.
            candidate="$PWD"
            while [ "$candidate" != "/" ]; do
              candidate="$(dirname "$candidate")"
              if is_pi_fowler_checkout "$candidate"; then
                printf '%s\n' "$candidate"
                return 0
              fi
            done
            return 1
          }

          # Prefer an explicit override, then a nearby pi-fowler checkout. This
          # is what makes settings persistent in HARBINGER: the checkout lives
          # on the always-mounted /workspace share rather than in the VM's
          # ephemeral home directory.
          if [ -n "''${PI_FOWLER_AGENT_DIR:-}" ]; then
            agent_dir="$PI_FOWLER_AGENT_DIR"
          elif checkout="$(find_checkout)"; then
            agent_dir="$checkout/agent"
          else
            agent_dir="$HOME/pi-fowler/agent"
          fi

          mkdir -p "$agent_dir"
          for file in AGENTS.md settings.json keybindings.json; do
            if [ ! -e "$agent_dir/$file" ]; then
              cp "${pi-fowler-agent-defaults}/$file" "$agent_dir/$file"
            fi
          done

          export PI_CODING_AGENT_DIR="$agent_dir"

          # Extensions have to live where pi looks for packages, not only in this
          # process's argv: /sessions children and subagent runners get their own
          # resource loaders, which see the agent directory but never the command
          # line. The links are stable paths, so agent/settings.json can name them
          # and stay free of store paths/rebuild churn.
          packages_dir="$agent_dir/nix/packages"
          mkdir -p "$packages_dir"
          ln -sfn ${pi-firecrawl}/lib/node_modules/pi-firecrawl "$packages_dir/pi-firecrawl"
          ln -sfn ${pi-subagents}/lib/node_modules/pi-subagents "$packages_dir/pi-subagents"
          ln -sfn ${pi-parallel-sessions}/lib/node_modules/pi-parallel-sessions "$packages_dir/pi-parallel-sessions"

          # Repos on the shared /workspace mount are owned by another uid, and
          # git refuses those as "dubious ownership" when pi runs as root.
          # Injecting the setting through GIT_CONFIG_* covers every git
          # subprocess pi spawns without touching the user's ~/.gitconfig.
          export GIT_CONFIG_COUNT=1
          export GIT_CONFIG_KEY_0=safe.directory
          export GIT_CONFIG_VALUE_0='*'

          # Point the Firecrawl extension at the self-hosted instance. An
          # explicitly exported FIRECRAWL_API_URL is respected.
          : "''${FIRECRAWL_API_URL:=${firecrawlUrl}}"
          export FIRECRAWL_API_URL

          # Repeat the packages as explicit extensions so a settings.json that
          # predates them (seeded copies are never overwritten) still gets the
          # extensions: pi canonicalizes through the links and loads each once.
          exec ${pkgs.pi-coding-agent}/bin/pi \
            --extension "$packages_dir/pi-firecrawl" \
            --extension "$packages_dir/pi-subagents" \
            --extension "$packages_dir/pi-parallel-sessions" \
            "$@"
        '';

        meta =
          pkgs.pi-coding-agent.meta
          // {
            description = "Pi coding agent with a self-hosted Firecrawl extension preinstalled and a version-controlled agent directory";
            mainProgram = "pi";
          };
      };
    in {
      default = pi-fowler;
      inherit pi-firecrawl pi-fowler pi-parallel-sessions pi-subagents;
    });

    overlays.default = final: prev: {
      pi-fowler = self.packages.${final.system}.pi-fowler;
    };

    devShells = forAllSystems ({pkgs, ...}: {
      default = pkgs.mkShell {
        packages = with pkgs; [
          nodejs
          git
        ];
      };
    });
  };
}
