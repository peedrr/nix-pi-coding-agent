{ config, wlib, lib, pkgs, ... }:
let
  cfg = config.pi;
in
{
  imports = [ wlib.modules.default ];

  options.pi = {
    codingAgentDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Directory for Pi mutable state (settings, auth, sessions,
        extensions, skills, prompts, themes).

        - `null` (default): {env}`PI_CODING_AGENT_DIR` is not set; both Pi
          and its extensions fall back to `$HOME/.pi/agent`. Recommended.
        - `"/abs/path"`: global state at an absolute path.

        Never use `~` values: environment variables are never tilde-expanded,
        and extensions resolve non-absolute values against the cwd, producing
        literal `<cwd>/~/.pi/agent` directories.
      '';
    };

    sessionDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Override the session storage directory.
        Defaults to `{var}`PI_CODING_AGENT_DIR`/sessions`.
        Sets {env}`PI_CODING_AGENT_SESSION_DIR`.
        Use an absolute path; `~` is never expanded in environment variables.
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
    }
    // lib.optionalAttrs (cfg.codingAgentDir != null) {
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
