{ config, wlib, lib, pkgs, ... }:
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

    sessionDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Override the session storage directory.
        Defaults to `{var}`PI_CODING_AGENT_DIR`/sessions`.
        Sets {env}`PI_CODING_AGENT_SESSION_DIR`.
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

    offline = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable all startup network operations.
        Sets {env}`PI_OFFLINE` = "1".
      '';
    };

    skipVersionCheck = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Skip the version update check at startup.
        Sets {env}`PI_SKIP_VERSION_CHECK` = "1".
      '';
    };

    skills = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to skills directories.
        Sets {env}`PI_SKILLS_PATHS` (colon-separated).
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to extensions directories.
        Sets {env}`PI_EXTENSIONS_PATHS` (colon-separated).
      '';
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to themes directories.
        Sets {env}`PI_THEMES_PATHS` (colon-separated).
      '';
    };

    promptTemplates = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to prompt template directories.
        Sets {env}`PI_PROMPT_TEMPLATES_PATHS` (colon-separated).
      '';
    };

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a custom {file}`models.json` file.
        Sets {env}`PI_MODELS_PATH`.
      '';
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra CLI arguments passed to Pi at startup.
        Use `--flag` for boolean flags, `--flag=value` for valued flags.
        Example: `[ "--verbose" "--model=gpt-4" ]`.
      '';
    };
  };

  config = {
    wrapperImplementation = "binary";

    meta.maintainers = [
      {
        name = "peedrr";
        github = "peedrr";
      }
    ];

    env = {
      PI_PACKAGE_DIR = "${config.package}/lib/node_modules/pi-monorepo";
      PI_CODING_AGENT_DIR = cfg.codingAgentDir;
    }
    // lib.optionalAttrs (cfg.sessionDir != null) {
      PI_CODING_AGENT_SESSION_DIR = cfg.sessionDir;
    }
    // lib.optionalAttrs cfg.offline {
      PI_OFFLINE = "1";
    }
    // lib.optionalAttrs cfg.skipVersionCheck {
      PI_SKIP_VERSION_CHECK = "1";
    }
    // lib.optionalAttrs (cfg.models != null) {
      PI_MODELS_PATH = toString cfg.models;
    }
    // lib.optionalAttrs (cfg.skills != [ ]) {
      PI_SKILLS_PATHS = lib.concatStringsSep ":" (map toString cfg.skills);
    }
    // lib.optionalAttrs (cfg.extensions != [ ]) {
      PI_EXTENSIONS_PATHS = lib.concatStringsSep ":" (map toString cfg.extensions);
    }
    // lib.optionalAttrs (cfg.themes != [ ]) {
      PI_THEMES_PATHS = lib.concatStringsSep ":" (map toString cfg.themes);
    }
    // lib.optionalAttrs (cfg.promptTemplates != [ ]) {
      PI_PROMPT_TEMPLATES_PATHS = lib.concatStringsSep ":" (map toString cfg.promptTemplates);
    };

    flags = lib.listToAttrs (
      map (flag:
        let
          parts = lib.splitString "=" flag;
        in
        if builtins.length parts == 1 then
          { name = flag; value = true; }
        else
          {
            name = builtins.head parts;
            value = lib.concatStringsSep "=" (builtins.tail parts);
          }
      ) cfg.extraFlags
    );

    runtimePkgs = [
      pkgs.git
      pkgs.ripgrep
      pkgs.fd
      pkgs.gnutar
      pkgs.unzip
    ] ++ cfg.extraPackages;
  };
}
