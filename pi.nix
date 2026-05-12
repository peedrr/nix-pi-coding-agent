{ lib, buildNpmPackage, fetchFromGitHub, nodejs, makeWrapper }:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.74.0";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    rev = "v${version}";
    sha256 = "0wz5n910q4q0xyx4m86h2rh05rlkr8frx7ibpwy0vwy3xhwslj60";
  };

  npmDepsSha256 = "sha256-lEXlHPXWgOnJ+msmkM6JSuoJmKpLggoVuXDDTrZcYAU="; # Will be replaced with correct hash on first build

  nativeBuildInputs = [ makeWrapper ];

  buildPhase = ''
    npm run build
  '';

  installPhase = ''
    pkgDir=$out/lib/node_modules/@earendil-works/pi-coding-agent
    mkdir -p $pkgDir

    # Copy built coding-agent artifacts
    cp -r packages/coding-agent/dist $pkgDir/
    cp -r packages/coding-agent/docs $pkgDir/ 2>/dev/null || true
    cp -r packages/coding-agent/examples $pkgDir/ 2>/dev/null || true
    cp packages/coding-agent/package.json $pkgDir/
    cp packages/coding-agent/README.md $pkgDir/ 2>/dev/null || true
    cp packages/coding-agent/CHANGELOG.md $pkgDir/ 2>/dev/null || true

    # Copy node_modules with resolved symlinks (includes built workspace deps)
    cp -rL node_modules $pkgDir/

    # Create the base executable wrapper
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/pi \
      --add-flags "$pkgDir/dist/cli.js" \
      --chdir "$pkgDir"
  '';

  meta = with lib; {
    description = "Minimal terminal coding harness";
    homepage = "https://pi.dev";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
