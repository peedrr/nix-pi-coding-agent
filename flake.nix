{
  description = "Pi coding agent wrapped with nix-wrapper-modules — global and per-project configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    wrappers.url = "github:BirdeeHub/nix-wrapper-modules";
  };

  outputs = { self, nixpkgs, wrappers }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # The reusable Pi wrapper module.
      # Other flakes can import this via `inputs.pi-wrapper.wrappers.pi`
      # and call `.wrap { inherit pkgs; pi.codingAgentDir = "./.pi"; }`.
      piModule = { config, wlib, lib, pkgs, ... }:
        let
          cfg = config.pi;
        in
        {
          imports = [ wlib.modules.default ];

          options.pi = {
            codingAgentDir = lib.mkOption {
              type = lib.types.str;
              default = "~/.pi/agent";
              description = ''
                Directory for Pi mutable state (settings, auth, sessions,
                extensions, skills, prompts, themes).

                - "~/.pi/agent" for global, cross-project state
                - "./.pi" for per-project, isolated state
              '';
            };

            extraPackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = ''
                Extra packages made available on Pi's PATH.
                Use this for tools Pi extensions or skills may shell out to
                (e.g. terraform, awscli, jq, pandoc).
              '';
            };
          };

          config = {
            # Environment variables Pi reads at runtime.
            # Note: config.package is set by the caller (evalPackage / .wrap).
            env = {
              # Point Pi to the read-only Nix store path for bundled assets
              # (themes, docs, README, package.json, export-html templates).
              # This is explicitly supported by Pi for Nix/Guix store paths.
              PI_PACKAGE_DIR = "${config.package}/lib/node_modules/@earendil-works/pi-coding-agent";

              # Mutable state directory. Relative paths resolve against cwd.
              PI_CODING_AGENT_DIR = cfg.codingAgentDir;
            };

            # Runtime dependencies Pi expects on PATH
            extraPackages = [
              pkgs.git
              pkgs.ripgrep
              pkgs.fd
              pkgs.nodejs
            ] ++ cfg.extraPackages;
          };
        };
    in
    {
      # Export the reusable wrapper module so other flakes can extend it.
      # Usage in another flake:
      #
      #   inputs.pi-wrapper.url = "path:/home/you/code/projects/tools/pi/on-nix";
      #   outputs = { self, nixpkgs, pi-wrapper, wrappers }:
      #     let
      #       pkgs = nixpkgs.legacyPackages.x86_64-linux;
      #       piPkg = pi-wrapper.packages.x86_64-linux.pi-coding-agent;
      #     in {
      #       packages.x86_64-linux.pi = (wrappers.lib.evalModules {
      #         modules = [
      #           ({ pkgs, wlib, ... }: {
      #             inherit pkgs;
      #             imports = [ wlib.modules.default pi-wrapper.wrappers.piModule ];
      #             package = piPkg;
      #             pi.codingAgentDir = "./.pi";
      #             pi.extraPackages = [ pkgs.terraform pkgs.jq ];
      #           })
      #         ];
      #         specialArgs = { inherit pkgs; };
      #       }).config.wrapper;
      #     };
      #
      wrappers.piModule = piModule;

      # Per-system packages
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          piPkg = pkgs.callPackage ./pi.nix { };
        in
        {
          # The unwrapped Pi package (useful if you want to wrap it yourself)
          pi-coding-agent = piPkg;

          # Default: globally-configured Pi with mutable state in ~/.pi/agent
          default = (wrappers.lib.evalModules {
            modules = [
              ({ pkgs, wlib, ... }: {
                inherit pkgs;
                imports = [ wlib.modules.default piModule ];
                package = piPkg;
                pi.codingAgentDir = "~/.pi/agent";
              })
            ];
            specialArgs = { inherit pkgs; };
          }).config.wrapper;
        }
      );

      # `nix run` support
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/pi";
        };
      });
    };
}
