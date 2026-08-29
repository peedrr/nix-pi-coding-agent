{ lib
, buildNpmPackage
, fetchFromGitHub
, fetchurl
, nodejs
, typescript-go
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-coding-agent";
  version = "0.84.4";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7z8OXao1PzmBEepDkIqVqyfQBPHulBlKcGymDYsnMvc=";
  };

  npmDepsHash = "sha256-/xBp9Tn3jbPMSzrBVzH0Fb5uBNiLC8JlT/q09Zf08lM=";
  npmDepsFetcherVersion = 2;

  npmWorkspace = "packages/coding-agent";

  # Skip native module rebuild for unneeded workspaces (e.g. canvas from web-ui)
  npmRebuildFlags = [ "--ignore-scripts" ];

  postPatch = ''
    cp ${./package-lock.v0.84.4.json} package-lock.json
  '';

  nativeBuildInputs = [
    typescript-go
  ];

  # pi-ai's model data lives in gitignored JSON files under
  # src/providers/data/ (generated upstream by `generate-models`, which
  # requires network). Source the prebuilt data from the published
  # @earendil-works/pi-ai npm tarball instead. The JSON must exist in
  # src/providers/data/ at compile time (tsgo with moduleResolution
  # NodeNext resolves the `import ... from "./data/<provider>.json"` for
  # real) and in dist/providers/data/ at runtime.
  piAiData = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${finalAttrs.version}.tgz";
    hash = "sha256-39PJKc7lpzhxmaCiTfwb4glvHqj1n/uChRmKDtAev5M=";
  };

  preBuild = ''
    # Seed pi-ai's gitignored model-data JSON from the npm tarball so tsgo
    # can resolve the `./data/<provider>.json` imports at compile time.
    mkdir -p packages/ai/src/providers/data
    tar -xf ${finalAttrs.piAiData} -C packages/ai/src/providers/data \
      --strip-components=4 package/dist/providers/data
  '';

  # Build workspace dependencies in order, then the coding-agent.
  # We invoke tsgo directly for workspace deps to skip pi-ai's
  # generate-models script which requires network access, then copy the
  # seeded model data into dist (mirroring upstream's build:offline).
  buildPhase = ''
    runHook preBuild

    # telemetry (added upstream in v0.84.0) must be built before
    # packages/ai and packages/agent, which import it. protocol and
    # client are also new in v0.84.0 (coding-agent depends on both).
    # Each build is guarded so older source trees (e.g. pinned v0.83.0)
    # still build.
    if [ -f packages/telemetry/tsconfig.build.json ]; then
      tsgo -p packages/telemetry/tsconfig.build.json
    fi
    if [ -f packages/protocol/tsconfig.build.json ]; then
      tsgo -p packages/protocol/tsconfig.build.json
    fi
    if [ -f packages/client/tsconfig.build.json ]; then
      tsgo -p packages/client/tsconfig.build.json
    fi
    tsgo -p packages/ai/tsconfig.build.json
    mkdir -p packages/ai/dist/providers/data
    cp -r packages/ai/src/providers/data/. packages/ai/dist/providers/data/

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

    # Replace workspace deps needed at runtime with real copies.
    # pi-ai's dist/providers/data (model JSON seeded from the npm tarball)
    # travels along with the packages/ai copy.
    for ws in @earendil-works/pi-ai:packages/ai \
              @earendil-works/pi-tui:packages/tui \
              @earendil-works/pi-agent-core:packages/agent \
              @earendil-works/pi-telemetry:packages/telemetry \
              @earendil-works/pi-protocol:packages/protocol \
              @earendil-works/pi-client:packages/client; do
      IFS=: read -r pkg src <<< "$ws"
      [ -d "$src" ] || continue
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
