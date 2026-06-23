# MicropleDev `.github`

Org-wide defaults and shared reusable workflows for the [MicropleDev](https://github.com/MicropleDev) organization.

GitHub treats a repo named `.github` specially: its `profile/README.md` is the public org-page front matter, and its `.github/workflows/*.yml` files are referenceable as reusable workflows from any other repo in the org.

## Contents

| Path | Purpose |
|---|---|
| `profile/README.md` | Public org-page README |
| `.github/workflows/` | Reusable workflows (`workflow_call`) shared across org repos |
| `.github/actions/` | Composite actions shared across org repos (currently: `minisign-sign`) |
| `docs/` | Conventions, signing policy, and contributor docs |
| (future) `.github/scripts/` | Shared shell scripts that workflows can source — added when something actually needs to be shared |

## Reusable workflows

| Workflow | Used by | Stable / dev |
|---|---|---|
| `.github/workflows/go-release.yml` | heisenberg, weather-server, sounddog, AlphaDog | stable cuts (manual) |
| `.github/workflows/go-dev-release.yml` | same | dev cuts (auto on push to main) |
| `.github/workflows/python-tarball-release.yml` | superdog, superdog-listener | stable cuts (manual) |
| `.github/workflows/python-tarball-dev-release.yml` | same | dev cuts (auto on push to main) |
| `.github/workflows/flutter-ui-release.yml` | (planned: watchdog, setup-dog — W6 not yet migrated) | stable cuts (manual) |
| `.github/workflows/flutter-ui-dev-release.yml` | (planned: same — W6 not yet migrated) | dev cuts (auto on push to main) |

Conventions (tag scheme, signing model, cadence) live in [docs/release-scheme.md](docs/release-scheme.md). Repo / service / package naming rules live in [docs/naming.md](docs/naming.md).

## Why this repo exists

Pre-Phase-0, the four Go service repos in the org each had a 200-line release workflow that differed only in `binary_name`, `version_pkg`, and `build_path`. The two Python repos and two Flutter UI repos had similar duplication. Three latent CI bugs (heisenberg missing GitCommit/BuildDate ldflags; superdog + superdog-listener + watchdog-os missing `prerelease:` flag) all stem from copy-paste drift.

Centralising the workflows means future signing changes (W7/W8), action-version bumps, and tag-scheme tweaks happen in one file instead of nine. Tracks: [MicropleDev/watchdog-os#52](https://github.com/MicropleDev/watchdog-os/issues/52) (OTA epic).
