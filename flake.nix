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
      pi-firecrawl = pkgs.runCommand "pi-firecrawl-0.2.0" {
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

      # Default files seeded into a brand-new agent directory. Existing files
      # are never overwritten, so user changes survive upgrades.
      pi-fowler-agent-defaults = pkgs.runCommand "pi-fowler-agent-defaults" {} ''
        mkdir -p $out
        cp ${./agent/AGENTS.md} $out/AGENTS.md
        cp ${./agent/settings.json} $out/settings.json
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
              "$PWD/../pi-fowler" \
              "/workspace/pi-fowler" \
              "$HOME/pi-fowler"; do
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
          for file in AGENTS.md settings.json; do
            if [ ! -e "$agent_dir/$file" ]; then
              cp "${pi-fowler-agent-defaults}/$file" "$agent_dir/$file"
            fi
          done

          export PI_CODING_AGENT_DIR="$agent_dir"

          # Point the Firecrawl extension at the self-hosted instance. An
          # explicitly exported FIRECRAWL_API_URL is respected.
          : "''${FIRECRAWL_API_URL:=${firecrawlUrl}}"
          export FIRECRAWL_API_URL

          exec ${pkgs.pi-coding-agent}/bin/pi \
            --extension ${pi-firecrawl}/lib/node_modules/pi-firecrawl \
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
      inherit pi-firecrawl pi-fowler;
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
