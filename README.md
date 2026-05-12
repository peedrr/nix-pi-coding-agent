# pi-on-nix

A Nix flake for the [Pi](https://pi.dev) terminal coding agent, featuring configurable global and per-project setups via [nix-wrapper-modules](https://github.com/BirdeeHub/nix-wrapper-modules).

## What This Flake Provides

Pi is a minimal terminal coding harness. This flake packages it for Nix with flexible configuration options.

| Output | Description |
|--------|-------------|
| `packages.<system>.pi-coding-agent` | The raw, unwrapped Pi package |
| `packages.<system>.default` | Pi with global config (`PI_CODING_AGENT_DIR = ~/.pi/agent`) |
| `wrappers.piModule` | Reusable nix-wrapper-modules module for custom wrapping |
| `nixosModules.pi` / `nixosModules.default` | NixOS module for declarative system-wide configuration |
| `apps.<system>.default` | `nix run` support for quick testing |

## Quick Start

Test Pi without installing:

```bash
nix run github:yourusername/pi-on-nix
```

## Usage Patterns

### Global Configuration (Default)

The default package uses `~/.pi/agent` for mutable state (settings, auth, sessions, extensions):

```nix
{
  inputs.pi.url = "github:yourusername/pi-on-nix";

  outputs = { self, nixpkgs, pi }: {
    packages.x86_64-linux.default = pi.packages.x86_64-linux.default;
  };
}
```

Install via `nix profile install` or add to your Home Manager packages.

### Per-Project Configuration

For isolated, project-specific Pi state:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pi.url = "github:yourusername/pi-on-nix";
    wrappers.url = "github:BirdeeHub/nix-wrapper-modules";
  };

  outputs = { self, nixpkgs, pi, wrappers }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      piPkg = pi.packages.x86_64-linux.pi-coding-agent;
    in {
      packages.x86_64-linux.my-pi = (wrappers.lib.evalModules {
        modules = [
          ({ pkgs, wlib, ... }: {
            inherit pkgs;
            imports = [ wlib.modules.default pi.wrappers.piModule ];
            package = piPkg;
            pi.codingAgentDir = "./.pi";
            pi.extraPackages = [ pkgs.terraform pkgs.jq pkgs.awscli2 ];
          })
        ];
        specialArgs = { inherit pkgs; };
      }).config.wrapper;
    };
}
```

Then in your project:

```bash
nix run .#my-pi
```

This keeps all Pi state (settings, auth, extensions) isolated to `./.pi` within your project.

### NixOS Module

For system-wide declarative configuration:

```nix
{ inputs, ... }: {
  imports = [ inputs.pi.nixosModules.default ];

  programs.pi.coding-agent = {
    enable = true;
    codingAgentDir = "~/.pi/agent";
    extraPackages = [ pkgs.terraform pkgs.jq ];
    
    # Optional: declarative skills, themes, extensions
    skills = [ /path/to/skills ];
    themes = [ /path/to/themes ];
    extensions = [ /path/to/extensions ];
    promptTemplates = [ /path/to/prompts ];
    models = /path/to/models.json;
    
    # Optional: extra CLI flags
    extraFlags = [ "--verbose" ];
  };
}
```

## Adding Extra Packages to PATH

Pi extensions and skills may need external tools. Use `extraPackages`:

```nix
pi.extraPackages = [
  pkgs.terraform
  pkgs.awscli2
  pkgs.jq
  pkgs.pandoc
  pkgs.ripgrep  # already included by default
  pkgs.fd       # already included by default
];
```

Default packages always available: `git`, `ripgrep`, `fd`, `nodejs`.

## Architecture: PI_PACKAGE_DIR + PI_CODING_AGENT_DIR

This flake uses a two-directory pattern explicitly supported by Pi:

| Variable | Purpose | Mutability |
|----------|---------|------------|
| `PI_PACKAGE_DIR` | Read-only Nix store path containing themes, docs, package.json, export-html templates | Immutable (Nix store) |
| `PI_CODING_AGENT_DIR` | Mutable state directory for settings, auth, sessions, extensions, skills | Mutable (user/project controlled) |

**Why this pattern?**

- **PI_PACKAGE_DIR** points to bundled assets that ship with Pi. These belong in the Nix store, version-locked and immutable.
- **PI_CODING_AGENT_DIR** is where Pi writes runtime state. Separating this allows flexibility: use `~/.pi/agent` for global state or `./.pi` for project isolation.

This mirrors how Guix packages Pi and enables pure, reproducible builds while keeping user data separate.

## NixOS Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable Pi system-wide |
| `package` | package | `pi-coding-agent` | Pi package to wrap |
| `codingAgentDir` | string | `"~/.pi/agent"` | Mutable state directory |
| `extraPackages` | list | `[]` | Extra packages on PATH |
| `skills` | list of paths | `[]` | Skills directories (sets `PI_SKILLS_PATHS`) |
| `extensions` | list of paths | `[]` | Extensions directories (sets `PI_EXTENSIONS_PATHS`) |
| `themes` | list of paths | `[]` | Themes directories (sets `PI_THEMES_PATHS`) |
| `promptTemplates` | list of paths | `[]` | Prompt template directories (sets `PI_PROMPT_TEMPLATES_PATHS`) |
| `models` | null or path | `null` | Custom models.json (sets `PI_MODELS_PATH`) |
| `extraFlags` | list of strings | `[]` | Extra CLI arguments |

## Auto-Update CI

This repository includes a GitHub Actions workflow that automatically updates Pi when new versions are released upstream.

**Schedule:** Daily at midnight UTC (`0 0 * * *`), plus manual trigger via `workflow_dispatch`.

**What it does:**

1. Checks [earendil-works/pi](https://github.com/earendil-works/pi) for new releases
2. Compares current version in `pi.nix` with latest upstream tag
3. Prefetches the source archive and computes the source hash
4. Extracts `package-lock.json` and computes `npmDepsHash`
5. Updates `pi.nix` with new version, source hash, and npm deps hash
6. Vendors the new `package-lock.json` as `package-lock.v{VERSION}.json`
7. Removes old vendored package-lock files
8. Verifies the build with `nix build .#pi-coding-agent`
9. Commits changes as `github-actions[bot]`
10. Creates a git tag for the new version
11. Pushes to the default branch

**Why vendoring?** Pi's `package-lock.json` is not included in the release tarball. We vendor it to ensure reproducible builds.

## Build Details

Pi is built from source using Nix's standard `buildNpmPackage`:

- **Build approach:** `nixpkgs`-proven `buildNpmPackage` with npm workspace support
- **Workspace:** `packages/coding-agent`
- **Skip:** `generate-models` step (requires network, but models are pre-generated in repo)
- **Build order:** `ai` → `tui` → `agent` → `coding-agent`
- **Post-install:** Replaces workspace symlinks with real copies for runtime

## Supported Platforms

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin`
- `aarch64-darwin`

## License

MIT (same as upstream Pi)
