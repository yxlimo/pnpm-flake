# pnpm-flake

`pnpm` packaged for Nix from the standalone tarball pnpm publishes on its
GitHub releases — the same artifact the official install script downloads, no
node dependency at runtime.

Linux only: `x86_64-linux`, `aarch64-linux`.

## Usage

Add the flake as an input:

```nix
{
  inputs.pnpm-flake.url = "github:yxlimo/pnpm-flake";

  # Optional, but avoids pulling a second copy of nixpkgs.
  inputs.pnpm-flake.inputs.nixpkgs.follows = "nixpkgs";
}
```

Install it — NixOS, Home Manager and a devShell all use the same attribute path:

```nix
environment.systemPackages = [ inputs.pnpm-flake.packages.${pkgs.system}.pnpm ];
# or: home.packages = [ inputs.pnpm-flake.packages.${pkgs.system}.pnpm ];
```

Try it without installing anything:

```bash
nix run github:yxlimo/pnpm-flake -- --version
```

If you would rather have `pkgs.pnpm` than a flake attribute, use the overlay:

```nix
nixpkgs.overlays = [ inputs.pnpm-flake.overlays.default ];

environment.systemPackages = [ pkgs.pnpm ];
```

`bin/pn`, `bin/pnx` and `bin/pnpx` are installed alongside `bin/pnpm`, matching
what pnpm's own installer creates.

### Pinning a version

Every update publishes a `v<version>` tag and a GitHub release, so you can pin a
readable version instead of a commit revision:

```nix
# Track upstream (recommended; flake.lock pins the exact revision anyway).
inputs.pnpm-flake.url = "github:yxlimo/pnpm-flake";

# Freeze one pnpm version.
inputs.pnpm-flake.url = "github:yxlimo/pnpm-flake/v12.17.0";
```

With a `git+https://` URL the ref must be written in full — `?ref=v12.17.0` is
looked up as a **branch** and fails with
`couldn't find remote ref refs/heads/v12.17.0`:

```nix
inputs.pnpm-flake.url = "git+https://github.com/yxlimo/pnpm-flake?ref=refs/tags/v12.17.0";
```

## How updates happen

`sources.json` is the single source of truth for the version and the per-platform
hashes. It is maintained by `bin/update-sources.sh`:

```
1. list pnpm releases, keep semver tags, take the highest     -> version
2. download each platform tarball and hash it (nix-prefetch-url)
3. write sources.json
```

**Both platforms are hashed on every run, on whatever machine runs the script.**
The tarballs are plain downloads, so an x86_64 runner can hash the arm64 one.
That is the whole point of this repository: a hash recomputed only for the host
machine silently rots for every other platform, and the breakage then shows up
on someone else's machine weeks later with a hash-mismatch error.

pnpm publishes two release lines at once (11.x LTS and 12.x stable). This
repository tracks one line — the highest semver wins, so `12.17.0` beats
`11.28.10` with no special casing.

Triggering is **event driven; there is no cron**:

- `repository_dispatch` (type `upstream-release`): sent by an external relay
  after upstream publishes a release;
- `workflow_dispatch`: manual catch-up (`gh workflow run update.yml`).

GitHub only delivers `release` events for releases of the repository itself, so
a repository that packages someone else's software needs a relay to poll
upstream and dispatch. The relay is not part of this repository (it runs as a
systemd timer on the consumer's server).

On a successful update the workflow commits `sources.json`, tags `v<version>`
and publishes a GitHub release listing both platform hashes.

## Notes

- Why not nixpkgs' `pnpm`: it lags upstream (12.9.0 when upstream was 12.16.1)
  and it is not this repository's job to decide when you upgrade.
- Why not the npm registry's `pnpm` package: its `install.js` downloads the
  binary again inside the build sandbox, which fails in a sandboxed build.
- The tarball ships `pnpm` and `dist/` side by side, and the binary resolves
  `dist/` relative to its own location, so the install phase keeps that sibling
  layout under `libexec/` and symlinks `bin/pnpm` at it.
- Only the `x64` and `arm64` Linux tarballs are packaged; musl, android and the
  BSD/macOS/Windows assets are not.

## Layout

| Path | What it is |
|---|---|
| `flake.nix` | flake outputs: `packages`, `overlays.default` |
| `package.nix` | the derivation; `sourcesFile` is an argument |
| `sources.json` | version and per-platform hashes, maintained by CI |
| `bin/update-sources.sh` | regenerate `sources.json` from the releases |
| `.github/workflows/update.yml` | update (dispatch-driven) and build (push/PR) jobs |
