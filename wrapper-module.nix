{ config, wlib, lib, pkgs, ... }:
{
  imports = [ wlib.modules.default ];

  options.codingAgentDir = lib.mkOption {
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

  options.sessionDir = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      Override the session storage directory.
      Defaults to `{var}`PI_CODING_AGENT_DIR`/sessions`.
      Sets {env}`PI_CODING_AGENT_SESSION_DIR`.
      Use an absolute path; `~` is never expanded in environment variables.
    '';
  };

  options.offline = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Disable all startup network operations.
      Sets {env}`PI_OFFLINE` = "1".
    '';
  };

  options.skipVersionCheck = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Skip the version update check at startup.
      Sets {env}`PI_SKIP_VERSION_CHECK` = "1".
    '';
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
      PI_PACKAGE_DIR = "${config.package}/lib/node_modules/pi-host/node_modules/@earendil-works/pi-coding-agent";
    }
    // lib.optionalAttrs (config.codingAgentDir != null) {
      PI_CODING_AGENT_DIR = config.codingAgentDir;
    }
    // lib.optionalAttrs (config.sessionDir != null) {
      PI_CODING_AGENT_SESSION_DIR = config.sessionDir;
    }
    // lib.optionalAttrs config.offline {
      PI_OFFLINE = "1";
    }
    // lib.optionalAttrs config.skipVersionCheck {
      PI_SKIP_VERSION_CHECK = "1";
    };

    runtimePkgs = [
      pkgs.git
      pkgs.ripgrep
      pkgs.fd
      pkgs.gnutar
      pkgs.unzip
      # npm/node: `pi install npm:...` and startup auto-install of missing
      # packages shell out to npm; fails on minimal hosts without node.
      pkgs.nodejs
    ];
  };
}
