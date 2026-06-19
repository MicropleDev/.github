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
| Go binary | `heisenberg-0.1.0-linux-arm64` + `.sha256` (+ `.minisig` post-W8) | `heisenberg-0.1.1-dev.20260618.abc1234-linux-arm64` + sidecars |
| Python tarball (W3) | `superdog-0.2.0.tar.zst` + `.sha256` (+ `.minisig`) | same with dev version |
| Flutter UI tarball (W5) | `watchdog-ui-0.1.0.tar.zst` + `.sha256` (+ `.minisig`) | same |
| watchdog-os bundle | `watchdog-bundle-0.1.0.tar.zst` + `.sha256` + `.minisig` + `manifest.json` | same |

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
