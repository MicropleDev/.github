# Release signing

WatchDog OS release artifacts are signed with [minisign](https://jedisct1.github.io/minisign/) (Ed25519). Public keys are committed to [`MicropleDev/watchdog-os/manifest/keys/`](https://github.com/MicropleDev/watchdog-os/tree/main/manifest/keys); secret keys live in the storage locations described below.

## Two-key model

| Channel | Public key | Used by | Secret-key handling |
|---|---|---|---|
| `stable` | `manifest/keys/wdos-stable.pub` (id `01FB8B9873285A05`) | Manual stable cuts via `go-release.yml` | Source of truth: offline (1Password). Staged into a **GH Actions environment secret** on each consumer repo, under an environment with required-reviewer approval. |
| `dev` | `manifest/keys/wdos-dev.pub` (id `0A08F649ED6E0F74`) | Auto dev cuts on push to main via `go-dev-release.yml` | **Org-level GH Actions secret** — visible to every org repo, no gating. |

The Pi-side OTA agent (`wd-updater`, Phase 2 of the OTA epic) accepts **only** the signature whose key matches the Pi's configured channel. A compromised dev key cannot ship a fake stable.

## Secret storage details

The two channels deliberately use different storage scopes — different threat models for each.

### Dev secrets — org-level (no gating)

Add at **Org Settings → Secrets and variables → Actions** on the `MicropleDev` org:

| Name | Value |
|---|---|
| `WDOS_DEV_MINISIGN_KEY` | full text of `wdos-dev.key` (run `cat wdos-dev.key`) |
| `WDOS_DEV_MINISIGN_PASSWORD` | password chosen at key-gen time |

Visibility: "All repositories" (or restrict to the Go service repos). Dev cuts fire on every push to main — gating them would defeat the auto-cadence.

### Stable secrets — per-repo environment, required-reviewer approval

Stable cuts are deliberate and infrequent; the secrets should require a human click before they're accessible.

In **each consumer repo** (heisenberg, weather-server, sports-server, gustavo — the four Go services), under **Settings → Environments → New environment**:

1. Name the environment `stable-release` (the consumer's wrapper passes this as the `environment` input — see below).
2. Configure **Required reviewers** = `mavis-dev` (or whoever should approve stable cuts).
3. Add the two secrets inside that environment:

| Name | Value |
|---|---|
| `WDOS_STABLE_MINISIGN_KEY` | full text of `wdos-stable.key` (from 1Password attachment) |
| `WDOS_STABLE_MINISIGN_PASSWORD` | password chosen at key-gen time |

The secrets are now unreachable to any workflow run until the configured reviewer clicks "Approve and deploy" on the pending run. The reusable `go-release.yml` workflow accepts `environment` as an input — when the caller passes `environment: stable-release`, GH applies that environment to the signing job, and the gating fires.

If you don't want the gating yet (small fleet, low-paranoia phase), skip the environment step entirely and put `WDOS_STABLE_MINISIGN_*` at the org level alongside the dev secrets. The `go-release.yml` workflow's `environment` input defaults to empty in that case.

## Consumer wrapper templates

### Dev (auto on push to main, no env gating)

```yaml
# .github/workflows/dev-release.yml in a Go consumer repo
name: Dev release
on:
  push:
    branches: [main]
    paths-ignore: ['**/*.md', '.github/**', 'docs/**']
jobs:
  dev-release:
    uses: MicropleDev/.github/.github/workflows/go-dev-release.yml@main
    with:
      binary_name: heisenberg
      version_pkg: heisenberg/pkg/version
      build_path: .
    secrets: inherit  # passes WDOS_DEV_MINISIGN_KEY/PASSWORD through
```

### Stable (manual, env-protected)

```yaml
# .github/workflows/release.yml in a Go consumer repo
name: Release
on:
  workflow_dispatch:
    inputs:
      bump_type:
        type: choice
        options: [patch, minor, major]
        required: true
jobs:
  release:
    uses: MicropleDev/.github/.github/workflows/go-release.yml@main
    with:
      binary_name: heisenberg
      version_pkg: heisenberg/pkg/version
      build_path: .
      bump_type: ${{ inputs.bump_type }}
      environment: stable-release   # gates secret access on required-reviewer approval
    secrets: inherit                # passes WDOS_STABLE_MINISIGN_KEY/PASSWORD through
```

If `secrets: inherit` is omitted, the sign step fails fast with a clear error pointing at the missing secret. If `environment:` is omitted from the consumer wrapper, the workflow still runs — just without env gating (secrets resolved from repo/org scope directly).

## Verifying a signed release

Once a signed bundle exists, anyone with the repo checked out can verify:

```bash
# minisign expects the signature alongside the file (<file>.minisig); use -x to
# point elsewhere
minisign -Vm watchdog-bundle-0.1.0.tar.zst -p manifest/keys/wdos-stable.pub
minisign -Vm watchdog-bundle-0.1.1-dev.20260618.abc1234.tar.zst -p manifest/keys/wdos-dev.pub
```

Exit 0 → signature valid. Non-zero → reject.

## Key rotation

If a key is suspected compromised:

1. Generate a replacement on a trusted offline machine: `minisign -G -p NEW.pub -s NEW.key`.
2. Commit the new `.pub` next to the existing one (don't delete the old yet) in `watchdog-os/manifest/keys/`.
3. Update the Pi provisioning script to bake **both** old and new public keys into `/etc/wd-updater/trusted-keys/`.
4. Push an OTA bundle that includes the new keys → wait until the fleet has it.
5. Rotate the Actions secret(s) to the new key.
6. Once you've confirmed the fleet has the new key, push another bundle that **drops** the old `.pub`. Old key is now untrusted by the fleet.

The composite action itself is key-agnostic — it just takes whatever `key`/`password` inputs you pass.

## Related issues

- [watchdog-os#60](https://github.com/MicropleDev/watchdog-os/issues/60) — W7 (composite action + key policy)
- [watchdog-os#61](https://github.com/MicropleDev/watchdog-os/issues/61) — W8 (wire signing into all release workflows)
- [watchdog-os#52](https://github.com/MicropleDev/watchdog-os/issues/52) — OTA epic
