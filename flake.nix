{
  description = "pnpm packaged for Nix from the standalone binaries pnpm publishes (Linux)";

  # Use git+https:// rather than the `github:` shorthand: the shorthand
  # resolves refs through the GitHub REST API, which is rate limited to 60
  # requests per hour per unauthenticated IP — a single `nix flake metadata` can
  # hit 403. git+https speaks the git protocol and is not subject to that limit.
  inputs.nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # Linux only: these are the platforms pnpm ships a standalone tarball for
      # that this repository actually serves.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system: {
        pnpm = nixpkgs.legacyPackages.${system}.callPackage ./package.nix { };
        default = self.packages.${system}.pnpm;
      });

      # For consumers that prefer `pkgs.pnpm` over a flake attribute.
      overlays.default = final: prev: {
        pnpm = final.callPackage ./package.nix { };
      };

      # No `checks`: `nix flake check` would build them on every system, and an
      # aarch64 binary cannot execute on an x86_64 host without binfmt
      # emulation. CI covers both instead — a real build on x86_64, evaluation
      # on aarch64.

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
