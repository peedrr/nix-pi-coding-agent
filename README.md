# nix-pi-coding-agent

Pi wrapped for Nix with [nix-wrapper-modules](https://github.com/BirdeeHub/nix-wrapper-modules).

## What you get

A Nix flake that wraps the [Pi](https://pi.dev) coding agent with full configurability:

- **`nix run github:peedrr/nix-pi-coding-agent`** — try it without installing
- **`packages.<system>.default`** — Pi with global config at `~/.pi/agent`
- **`packages.<system>.pi`** — the unwrapped package for custom wrapping
- **`wrappers.piModule`** — reusable module supporting `.wrap`, `.apply`, `.eval`
- **`nixosModules.pi`** — NixOS module for declarative system-wide config

## Why it works well

The wrapper separates immutable Nix store assets from mutable user state:

| Variable | What it points to | Managed by |
|----------|-------------------|------------|
| `PI_PACKAGE_DIR` | Read-only themes, docs, templates in the Nix store | Nix |
| `PI_CODING_AGENT_DIR` | Your settings, auth, sessions, extensions | You |

This means reproducible builds without sacrificing user control. Pi gets the correct bundled assets from the exact version it was tested with, while your config lives wherever you want — `~/.pi/agent` globally or `./.pi` per-project.

The wrapper uses nix-wrapper-modules' binary backend for fast startup (~4ms overhead) and provides every configuration option Pi supports as Nix options.

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

  wrappers.pi = {
    enable = true;
    package = inputs.pi.packages.x86_64-linux.pi;
    codingAgentDir = "~/.pi/agent";
    extraPackages = [ pkgs.terraform ];
    extraFlags = [ "--verbose" ];
  };
}
```

### Available options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `codingAgentDir` | string | `"~/.pi/agent"` | Mutable state directory |
| `sessionDir` | null or string | `null` | Override session directory |
| `extraPackages` | list of packages | `[]` | Extra tools on PATH |
| `offline` | bool | `false` | Disable network at startup |
| `skipVersionCheck` | bool | `false` | Skip update checks |
| `skills` | list of paths | `[]` | Skills directories |
| `extensions` | list of paths | `[]` | Extension directories |
| `themes` | list of paths | `[]` | Theme directories |
| `promptTemplates` | list of paths | `[]` | Prompt template directories |
| `models` | null or path | `null` | Custom models.json |
| `extraFlags` | list of strings | `[]` | CLI args. `--flag` for booleans, `--flag=val` for values |

Default tools on PATH: `git`, `ripgrep` (`rg`), `fd`, `tar`, `unzip`.

## Supported platforms

`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`

## License

MIT
