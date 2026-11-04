# pnpm, from the standalone tarball pnpm publishes on its GitHub releases —
# the same artifact the official install script downloads.
#
# Why not the npm registry's `pnpm` package: its install.js downloads the
# binary again inside the build sandbox, which fails in a sandboxed build. The
# release tarball already contains the binary plus dist/, so nothing is fetched
# at build time.
#
# The tarball ships `pnpm` and `dist/` side by side, and the binary resolves
# `dist/` relative to its own location — so the install phase preserves that
# sibling layout under libexec/ and symlinks bin/pnpm at it.
#
# Version and per-platform hashes live in sources.json, maintained by
# bin/update-sources.sh. Both platforms are always hashed together: a hash that
# is only recomputed for the machine doing the update silently rots for every
# other platform, and the failure then shows up on someone else's machine.
{
  lib,
  stdenv,
  fetchurl,
  sourcesFile ? ./sources.json,
}:

let
  sources = lib.importJSON sourcesFile;
  system = stdenv.hostPlatform.system;
  platform =
    sources.platforms.${system}
      or (throw "pnpm: unsupported system '${system}'; supported: ${lib.concatStringsSep ", " (lib.attrNames sources.platforms)}");
in
stdenv.mkDerivation {
  pname = "pnpm";
  version = sources.version;

  src = fetchurl {
    url = "https://github.com/pnpm/pnpm/releases/download/v${sources.version}/${platform.tarball}";
    hash = platform.hash;
  };

  # The tarball's top level *is* the install root (pnpm + dist/).
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec
    # The launcher finds dist/ next to itself, so keep them as siblings.
    cp -a dist $out/libexec/dist
    install -Dm755 pnpm $out/libexec/pnpm
    ln -s $out/libexec/pnpm $out/bin/pnpm
    # Shims pnpm's own installation creates; users call these too.
    for n in pn pnx pnpx; do
      ln -s $out/libexec/pnpm $out/bin/$n
    done
    runHook postInstall
  '';

  meta = {
    description = "Fast, disk space efficient package manager (upstream standalone binary)";
    homepage = "https://pnpm.io/";
    changelog = "https://github.com/pnpm/pnpm/releases";
    license = lib.licenses.mit;
    mainProgram = "pnpm";
    platforms = lib.attrNames sources.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
