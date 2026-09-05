# nix-pi-coding-agent

Pi wrapped for Nix with [nix-wrapper-modules](https://github.com/BirdeeHub/nix-wrapper-modules).

## What you get

A Nix flake that wraps the [Pi](https://pi.dev) coding agent with full configurability:

- **`nix run github:peedrr/nix-pi-coding-agent`** — try it without installing
- **`packages.<system>.default`** — Pi with global config at `~/.pi/agent`
- **`packages.<system>.pi`** — the unwrapped package for custom wrapping
- **`wrappers.piModule`** — reusable module supporting `.wrap`, `.apply`, `.eval`
- **`nixosModules.pi`** — NixOS module for declarative system-wide config

The package is built from the published `@earendil-works/pi-coding-agent` npm
 tarball (prebuilt `dist/` bundle), with the dependency tree materialised by
 `npm ci` so that extensions such as `pi-subagents` can resolve host packages
 from the installation root.

## Why it works well

The wrapper separates immutable Nix store assets from mutable user state:

| Variable | What it points to | Managed by |
|----------|-------------------|------------|
| `PI_PACKAGE_DIR` | Read-only themes, docs, templates in the Nix store | Nix |
| `PI_CODING_AGENT_DIR` | Your settings, auth, sessions, extensions | You (unset by default: Pi and its extensions fall back to `$HOME/.pi/agent`) |

This means reproducible builds without sacrificing user control. Pi gets the correct bundled assets from the exact version it was tested with, while your config lives wherever you want — `~/.pi/agent` globally or `./.pi` per-project.

The wrapper uses nix-wrapper-modules' binary backend for fast startup (~4ms overhead). Note that because the binary backend embeds environment values as literals (no shell runs at exec time), path options must be absolute or explicitly cwd-relative like `"./.pi"` — `~` is never expanded.

## How to use it

### Quick test

```bash
nix run github:peedrr/nix-pi-coding-agent
```

### In your flake

```nix
{
  inputs.pi.url = "github:peedrr/nix-pi-coding-agent";

  outputs = { self, nixpkgs, pi }: {
    packages.x86_64-linux.default = pi.packages.x86_64-linux.default;
  };
}
```

### Per-project config

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pi.url = "github:peedrr/nix-pi-coding-agent";
  };

  outputs = { self, nixpkgs, pi }:
    let pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages.x86_64-linux.my-pi = pi.wrappers.piModule.wrap {
        inherit pkgs;
        package = pi.packages.x86_64-linux.pi;
        pi.codingAgentDir = "./.pi";
        pi.extraPackages = [ pkgs.terraform pkgs.awscli2 ];
      };
    };
}
```

### NixOS module

```nix
{ inputs, pkgs, ... }: {
  imports = [ inputs.pi.nixosModules.pi ];

  # The module enables itself by default; shown here for clarity.
  wrappers.pi = {
    enable = true;
    package = inputs.pi.packages.x86_64-linux.pi;
    # codingAgentDir defaults to null -> Pi uses "$HOME/.pi/agent".
    extraPackages = [ pkgs.terraform ];
    extraFlags = [ "--verbose" ];
  };
}
```

### Available options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `codingAgentDir` | null or string | `null` | Mutable state directory. `null` = unset = `$HOME/.pi/agent`. Never use `~` values |
| `sessionDir` | null or string | `null` | Override session directory (absolute path) |
| `extraPackages` | list of packages | `[]` | Extra tools on PATH |
| `offline` | bool | `false` | Disable network at startup |
| `skipVersionCheck` | bool | `false` | Skip update checks |
| `extraFlags` | list of strings | `[]` | CLI args. `--flag` for booleans, `--flag=val` for values |

Extensions, skills, themes, and prompt templates are intentionally **not**
wrapper options. Manage them through Pi's own mechanisms — `settings.json`
(`packages` with `npm:`/`git:` sources) and project-level `.pi/settings.json`.

Default tools on PATH: `git`, `ripgrep` (`rg`), `fd`, `tar`, `unzip`.

## Supported platforms

`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`

## License

MIT
