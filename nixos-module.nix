{ self, wrappers }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.pi.coding-agent;

  # Build the wrapped Pi package by evaluating our wrapper module
  # with the user-supplied configuration.
  wrappedPi = (wrappers.lib.evalModules {
    modules = [
      ({ pkgs, wlib, ... }:
        let
          # Convert extraFlags list to a flags attrset.
          # Empty values are filtered out so bare flags don't get passed
          # an empty-string argument.
          extraFlagsAttrs = lib.listToAttrs (
            map (flag: { name = flag; value = ""; }) cfg.extraFlags
          );
        in
        {
          inherit pkgs;
          imports = [ wlib.modules.default self.wrappers.piModule ];
          package = cfg.package;
          pi.codingAgentDir = cfg.codingAgentDir;
          pi.extraPackages = cfg.extraPackages;
          flags = extraFlagsAttrs;
          env = lib.optionalAttrs (cfg.models != null) {
            PI_MODELS_PATH = toString cfg.models;
          } // lib.optionalAttrs (cfg.skills != [ ]) {
            PI_SKILLS_PATHS = lib.concatStringsSep ":" (map toString cfg.skills);
          } // lib.optionalAttrs (cfg.extensions != [ ]) {
            PI_EXTENSIONS_PATHS = lib.concatStringsSep ":" (map toString cfg.extensions);
          } // lib.optionalAttrs (cfg.themes != [ ]) {
            PI_THEMES_PATHS = lib.concatStringsSep ":" (map toString cfg.themes);
          } // lib.optionalAttrs (cfg.promptTemplates != [ ]) {
            PI_PROMPT_TEMPLATES_PATHS = lib.concatStringsSep ":" (map toString cfg.promptTemplates);
          };
        })
    ];
    specialArgs = { inherit pkgs; };
  }).config.wrapper;
in
{
  options.programs.pi.coding-agent = {
    enable = lib.mkEnableOption "Pi coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.pi-coding-agent;
      description = ''
        The Pi coding agent package to wrap.
        Defaults to the unwrapped package from this flake.
      '';
    };

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

    skills = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to skills directories. These are exposed via the
        {env}`PI_SKILLS_PATHS` environment variable.
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to extensions directories. These are exposed via the
        {env}`PI_EXTENSIONS_PATHS` environment variable.
      '';
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to themes directories. These are exposed via the
        {env}`PI_THEMES_PATHS` environment variable.
      '';
    };

    promptTemplates = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to prompt templates directories. These are exposed via the
        {env}`PI_PROMPT_TEMPLATES_PATHS` environment variable.
      '';
    };

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a custom {file}`models.json` file.
        Exposed via the {env}`PI_MODELS_PATH` environment variable.
      '';
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra raw CLI arguments to pass to Pi.
        Each string is passed as-is to the wrapper script.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wrappedPi ];
  };
}
