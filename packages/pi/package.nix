{ lib
, buildNpmPackage
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-coding-agent";
  version = "0.85.1";

  # Synthetic npm root: package.json declares the published pi-coding-agent
  # tarball plus the optional packages that pi-subagents background children
  # need resolvable from the pi package root.  npm ci (via npmConfigHook)
  # materialises the whole tree, honouring the upstream npm-shrinkwrap.json.
  src = ./.;

  npmDepsHash = "sha256-8EWNpDsV36djWp1cnSy0aKlgVRa+p7X6b2u/iLMIZAw=";
  npmDepsFetcherVersion = 2;

  npmRebuildFlags = [ "--ignore-scripts" ];

  postPatch = ''
    cp ${./package-lock.v${finalAttrs.version}.json} package-lock.json
  '';

  # The published tarball is already built; nothing to compile here.
  dontNpmBuild = true;

  postInstall = ''
    mkdir -p "$out/bin"
    ln -s "$out/lib/node_modules/pi-host/node_modules/.bin/pi" "$out/bin/pi"
  '';

  meta = {
    description = "Pi coding agent (built from the published npm tarball)";
    homepage = "https://pi.dev";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    mainProgram = "pi";
  };
})
