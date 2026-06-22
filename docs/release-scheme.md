# MicropleDev release scheme

Conventions enforced by the reusable workflows in this repo. Cross-references the OTA epic [MicropleDev/watchdog-os#52](https://github.com/MicropleDev/watchdog-os/issues/52).

## Tag convention

| Channel | Tag form | `prerelease` flag |
|---|---|---|
| Stable | `v{MAJOR.MINOR.PATCH}` (e.g. `v0.1.0`) | `false` |
| Dev | `v{MAJOR.MINOR.PATCH}-dev.{YYYYMMDD}.{shortsha}` (e.g. `v0.1.1-dev.20260618.abc1234`) | `true` |

- Tag string alone identifies the channel — no API call needed.
- The `prerelease` API flag also matches (belt-and-suspenders).
- Filenames drop the `v` prefix (tag `v0.1.0` → asset `heisenberg-0.1.0-linux-arm64`).
- Dev base = `git tag -l 'v*.*.*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1` + 1 patch. The `grep` filter is **mandatory** — without it, dev tags like `v1.2.3-dev.…` match `v*.*.*` and corrupt the base derivation. NOT a `VERSION` file (drift trap).
- Dev timestamp is `date -u +%Y%m%d` (date only — shortsha disambiguates intra-day).

## Cadence

| Trigger | Result |
|---|---|
| Push to `main` of a consumer repo | Auto dev cut via `go-dev-release.yml` |
| Manual `workflow_dispatch` on consumer repo's `release.yml` with `bump_type: patch|minor|major` | Stable cut via `go-release.yml` |

Stable cadence is naturally slow (weeks/months); automating it adds risk without saving time. Friends-only fleet → human decides what ships.

## Signing

- Two minisign keys: `wdos-stable.key` (offline source-of-truth in 1Password; staged as Actions secret `WDOS_STABLE_MINISIGN_KEY` for the stable workflow, ideally environment-protected) + `wdos-dev.key` (Actions secret `WDOS_DEV_MINISIGN_KEY` + `WDOS_DEV_MINISIGN_PASSWORD`).
- Public keys committed at [MicropleDev/watchdog-os/manifest/keys/](https://github.com/MicropleDev/watchdog-os/tree/main/manifest/keys).
- Every release workflow signs via the [`actions/minisign-sign`](../.github/actions/minisign-sign/action.yml) composite action — produces `{asset}.minisig` alongside `{asset}.sha256`.
- Consumer wrappers must include `secrets: inherit` so the secrets pass through to the reusable workflow.
- Full key-management policy + verification commands: [`SIGNING.md`](SIGNING.md).

## Asset shape per type

| Type | Stable example | Dev example |
|---|---|---|
| Go binary | `heisenberg-0.1.0-linux-arm64` + `.sha256` + `.minisig` | `heisenberg-0.1.1-dev.20260618.abc1234-linux-arm64` + sidecars |
| Python tarball | `superdog-0.2.0.tar.zst` + `.sha256` + `.minisig` | same with dev version |
| Flutter UI tarball (W5) | `watchdog-ui-0.1.0.tar.zst` + `.sha256` + `.minisig` | same |
| watchdog-os bundle | `watchdog-bundle-0.1.0.tar.zst` + `.sha256` + `.minisig` + `manifest.json` | same |

## Python `scripts/build-bundle.sh` contract

Python packaging is more bespoke per repo than Go (apt extras, model
pre-downloads, distinct source-file sets). The reusable Python workflows
delegate to a per-repo `scripts/build-bundle.sh` script that the consumer
repo provides. The reusable workflow invokes it with these env vars set:

| Env var | Value | Example |
|---|---|---|
| `PACKAGE_NAME` | the `package_name` input | `superdog` |
| `VERSION` | resolved version (no `v` prefix) | `0.2.0` or `0.2.1-dev.20260619.abc1234` |
| `BUNDLE_DIR` | staging dir the script should populate | `dist/superdog-0.2.0` |
| `ASSET_PATH` | output tarball the script must produce | `dist/superdog-0.2.0.tar.zst` |

The script is responsible for:
1. Installing any apt build deps it needs.
2. Creating the venv and `pip install -r requirements.txt` (and any extras).
3. Optionally pre-downloading models / assets (e.g. Piper voice, openwakeword).
4. Copying source files into `$BUNDLE_DIR`.
5. Producing `$ASSET_PATH` (tar.zst) and `$ASSET_PATH.sha256`.

The reusable workflow then signs the asset with minisign and publishes it. The script must be executable (`chmod +x scripts/build-bundle.sh`).

A canonical example lives in [`scripts/python-bundle-example.sh`](../scripts/python-bundle-example.sh) of this repo.

## Flutter `scripts/build-bundle.sh` contract

The Flutter UI workflows (`flutter-ui-release.yml` / `flutter-ui-dev-release.yml`) use the same delegation pattern. The reusable workflow invokes `scripts/build-bundle.sh` with these env vars set:

| Env var | Value | Example |
|---|---|---|
| `PACKAGE_NAME` | the `ui_name` input | `watchdog-ui` |
| `VERSION` | resolved version (no `v` prefix) | `0.1.0` or `0.1.1-dev.20260619.abc1234` |
| `BUNDLE_DIR` | staging dir the script may use | `dist/watchdog-ui-0.1.0` |
| `ASSET_PATH` | output tarball the script must produce | `dist/watchdog-ui-0.1.0.tar.zst` |
| `GIT_COMMIT` | full HEAD commit SHA | (so the script can pass it as a `--dart-define`) |
| `BUILD_DATE` | ISO8601 UTC at workflow start | same |

Pass-through env vars from the consumer's secrets/vars scope (unset values become empty strings — script's choice how to handle):

| Var | Source | Typical use |
|---|---|---|
| `HEISENBERG_TOKEN` | secret | `--dart-define=HEISENBERG_TOKEN=...` |
| `GITHUB_APP_TOKEN` | named secret from caller's `secrets:` block | Pre-minted GitHub App installation token for authenticating `flutter pub get` against private deps (`dog-libs`, `wd-weather`). See "Two-job wrapper pattern for private pub deps" below. |
| `API_BASE_URL` / `WEATHER_API_BASE_URL` / `SOUNDDOG_API_BASE_URL` | vars | `--dart-define=...` |

### Private pub deps (GitHub App token)

If your Flutter app pulls private deps via `flutter pub get` (e.g. `dog-libs`, `wd-weather`), the reusable workflow mints a GitHub App installation token internally — you just need `WEATHER_APP_ID` and `WEATHER_APP_PRIVATE_KEY` set as secrets in your caller's scope.

```yaml
# .github/workflows/release.yml in a consumer repo
name: Release
permissions:
  contents: write
on:
  workflow_dispatch: { inputs: { bump_type: { type: choice, options: [patch, minor, major], required: true } } }

jobs:
  release:
    uses: MicropleDev/.github/.github/workflows/flutter-ui-release.yml@<sha>
    with:
      ui_name: watchdog-ui
      flutter_version: "3.35.3"
      bump_type: ${{ inputs.bump_type }}
      environment: stable-release
    secrets: inherit
```

The reusable workflow's `Mint GitHub App installation token` step runs only when both `WEATHER_APP_ID` and `WEATHER_APP_PRIVATE_KEY` are set; otherwise it's skipped and `GITHUB_APP_TOKEN` in the build script's env stays empty (fine for consumers without private deps).

> Two pitfalls worth knowing for future migrations:
>
> 1. **`environment:` is NOT allowed on a job that uses `uses:`** to call a reusable workflow. Env scoping for environment-protected secrets must happen via the reusable workflow's `environment: ${{ inputs.environment }}` declaration (combined with `secrets: inherit` from the caller — that's how env-scoped secrets resolve correctly in the reusable workflow's job context).
> 2. **Declaring a `secrets:` block on `workflow_call` makes it STRICT** — only declared secrets can be passed. Combine with `secrets: inherit` from the caller for maximum flexibility (any caller-scope secret flows through; resolution happens in the reusable workflow's job with its env scope).

The script is responsible for:
1. Installing `flutterpi_tool` (`flutter pub global activate flutterpi_tool`) — the reusable workflow installs the Flutter SDK itself via subosito/flutter-action.
2. Authenticating to private pub-deps if needed (write to `~/.netrc` or `~/.config/git/credentials` using `WEATHER_APP_*` and a generated GitHub App token).
3. Running `flutter pub get` (private-deps auth must be in place first).
4. Building via `flutterpi_tool build --arch=arm64 --cpu=pi4 --release ...` with whatever `--dart-define` flags the app needs.
5. Locating the flutter-pi output dir (varies between `build/flutter-pi/<arch>/<mode>/` etc.).
6. Packaging the output dir into `$ASSET_PATH` (tar.zst) at root level (no wrapper directory — flutter-pi expects files at the root of the unpacked dir).
7. Producing `$ASSET_PATH.sha256`.

The reusable workflow then signs `$ASSET_PATH` with minisign (producing `${ASSET_PATH}.minisig`) and publishes the release with the three files.

A canonical example will land alongside W6 (the consumer migration). The shape is similar to `scripts/python-bundle-example.sh` but with `flutterpi_tool` instead of `pip install`.

## Bundle channel selection (watchdog-os)

- `CHANNEL: stable` lane → per component picks `prerelease=false AND tag matches v{x.y.z}`. Bundle signed with stable key. `latest-stable.json` pointer.
- `CHANNEL: dev` lane → per component picks `prerelease=true AND tag matches v{x.y.z}-dev.…`. Bundle signed with dev key. `latest-dev.json` pointer.
- Per-component picker: prefer matching-channel, fall back to stable if no matching dev. **Never the reverse.**
- Bundle tag form follows the LANE, not contents — a `dev` lane always produces a `-dev.…` bundle tag even if every component happened to resolve to a stable. So a `stable`-channel Pi can never accidentally receive a debug-lane-built bundle.

## Pre-Phase-0 latent bugs surfaced + fixed

| Bug | Tracked | Status |
|---|---|---|
| heisenberg release.yml + dev-release.yml never injected `GitCommit`/`BuildDate` via ldflags (other 3 Go repos did) | [heisenberg#65](https://github.com/MicropleDev/heisenberg/issues/65) (B1) | ✅ fixed |
| superdog + superdog-listener + watchdog-os build-bundle.yml missing `prerelease:` key — `-dev.` tag would publish as stable | superdog#19 (B2), superdog-listener#26 (B3), watchdog-os#53 (B4) | ✅ fixed |

This file is the source of truth. Update here when conventions change.
