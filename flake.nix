{
  description = "pi-fowler — pi coding agent with the Firecrawl extension baked in";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      });
  in {
    packages = forAllSystems ({pkgs, ...}: let
      # -----------------------------------------------------------------
      # pi-firecrawl — official Firecrawl extension for pi
      #
      # Shipped as TypeScript source; pi's jiti loader reads src/index.ts
      # directly, so we only need to install the package together with its
      # runtime dependency (@mendable/firecrawl-js).
      # -----------------------------------------------------------------
      pi-firecrawl = pkgs.buildNpmPackage {
        pname = "pi-firecrawl";
        version = "0.1.0";

        src = pkgs.fetchFromGitHub {
          owner = "firecrawl";
          repo = "pi-firecrawl";
          rev = "2d7e8966ad63744fa7d5932f7bd5b4a78eddb894";
          hash = "sha256-1jbWRlQh72qoGUf2Bl220ZGKVzH/AsDgrS9weGgxb2I=";
        };

        npmDepsHash = "sha256-+ox5eIPBF9eY0yPw5IL4LypRSxZ1sz8JCFaDjmZ2DuU=";

        # Only the runtime dep tree is needed; peer deps are supplied by pi.
        npmFlags = ["--omit=dev" "--legacy-peer-deps"];

        # No compilation step for this package; install as-is.
        dontNpmBuild = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib/node_modules/pi-firecrawl
          cp -r . $out/lib/node_modules/pi-firecrawl
          runHook postInstall
        '';

        meta = {
          description = "Official Firecrawl extension for the Pi coding agent";
          homepage = "https://github.com/firecrawl/pi-firecrawl";
          license = pkgs.lib.licenses.mit;
        };
      };

      # -----------------------------------------------------------------
      # pi-fowler — pi with the Firecrawl extension loaded on every run
      #
      # We wrap `pi` and inject `-e <pi-firecrawl>` rather than replacing the
      # agent directory, so the user's writable ~/.pi/agent (settings,
      # sessions, auth) keeps working normally.
      # -----------------------------------------------------------------
      pi-fowler = pkgs.symlinkJoin {
        name = "pi-fowler-${pkgs.pi-coding-agent.version}";
        paths = [pkgs.pi-coding-agent];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/pi \
            --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.nodejs]} \
            --add-flags "--extension ${pi-firecrawl}/lib/node_modules/pi-firecrawl"
        '';

        meta = pkgs.pi-coding-agent.meta // {
          description = "Pi coding agent with the Firecrawl extension preinstalled";
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
