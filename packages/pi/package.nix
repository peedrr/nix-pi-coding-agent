{ lib
, buildNpmPackage
, fetchFromGitHub
, nodejs
, typescript-go
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-coding-agent";
  version = "0.74.0";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wEiqOezD8w08vyuenh3Kk+YCYBbQoEq67wATDEKy5XM=";
  };

  npmDepsHash = "sha256-QylliziiKg7ZPNCu5zc75FjxMKmeODzYrhjYmys5Rro=";
  npmDepsFetcherVersion = 2;

  npmWorkspace = "packages/coding-agent";

  # Skip native module rebuild for unneeded workspaces (e.g. canvas from web-ui)
  npmRebuildFlags = [ "--ignore-scripts" ];

  postPatch = ''
    cp ${./package-lock.v0.74.0.json} package-lock.json
  '';

  nativeBuildInputs = [
    typescript-go
  ];

  # Skip generate-models since it requires network access
  # (models.generated.ts is committed to the repo).
  preBuild = ''
    substituteInPlace packages/ai/package.json \
      --replace-fail '"build": "npm run generate-models && npm run generate-image-models && tsgo -p tsconfig.build.json"' \
                     '"build": "tsgo -p tsconfig.build.json"'
  '';

  # Build workspace dependencies in order, then the coding-agent.
  # We invoke tsgo directly for workspace deps to skip pi-ai's
  # generate-models script which requires network access.
  buildPhase = ''
    runHook preBuild

    tsgo -p packages/ai/tsconfig.build.json
    tsgo -p packages/tui/tsconfig.build.json --target esnext
    tsgo -p packages/agent/tsconfig.build.json
    npm run build --workspace=packages/coding-agent

    runHook postBuild
  '';

  # npm workspace symlinks in the output point into packages/ which
  # doesn't exist there. Replace runtime deps with built content and
  # delete the rest.
  postInstall = ''
    local nm="$out/lib/node_modules/pi-monorepo/node_modules"

    # Replace workspace deps needed at runtime with real copies
    for ws in @earendil-works/pi-ai:packages/ai \
              @earendil-works/pi-tui:packages/tui \
              @earendil-works/pi-agent-core:packages/agent; do
      IFS=: read -r pkg src <<< "$ws"
      if [ -L "$nm/$pkg" ]; then
        rm "$nm/$pkg"
        cp -r "$src" "$nm/$pkg"
      elif [ ! -e "$nm/$pkg" ]; then
        cp -r "$src" "$nm/$pkg"
      fi
    done

    # Delete remaining workspace symlinks
    find "$nm" -type l -lname '*/packages/*' -delete

    # Clean up now-dangling .bin symlinks
    find "$nm/.bin" -xtype l -delete 2>/dev/null || true
  '';

  meta = {
    description = "Minimal terminal coding harness";
    homepage = "https://pi.dev";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    mainProgram = "pi";
  };
})
