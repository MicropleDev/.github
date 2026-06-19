# Release signing

WatchDog OS release artifacts are signed with [minisign](https://jedisct1.github.io/minisign/) (Ed25519). Public keys are committed to [`MicropleDev/watchdog-os/manifest/keys/`](https://github.com/MicropleDev/watchdog-os/tree/main/manifest/keys); secret keys live as described below.

## Two-key model

| Channel | Public key | Secret-key storage | Used for |
|---|---|---|---|
| `stable` | `manifest/keys/wdos-stable.pub` (id `01FB8B9873285A05`) | Offline (1Password) + GH Actions secret `WDOS_STABLE_MINISIGN_KEY` (org-level, environment-protected) | Manual stable cuts via `go-release.yml` |
| `dev` | `manifest/keys/wdos-dev.pub` (id `0A08F649ED6E0F74`) | GH Actions secret `WDOS_DEV_MINISIGN_KEY` (org-level) | Auto dev cuts on push to main via `go-dev-release.yml` |

The Pi-side OTA agent (`wd-updater`, Phase 2 of the OTA epic) accepts **only** the signature whose key matches the Pi's configured channel. A compromised dev key cannot ship a fake stable.

## One-time setup of GH Actions secrets

Both signing flows pull their key + password from these org-level secrets:

| Secret name | Value | Required for |
|---|---|---|
| `WDOS_DEV_MINISIGN_KEY` | full text of `wdos-dev.key` (run `cat wdos-dev.key`) | dev releases |
| `WDOS_DEV_MINISIGN_PASSWORD` | password chosen at key-gen time | dev releases |
| `WDOS_STABLE_MINISIGN_KEY` | full text of `wdos-stable.key` (from 1Password attachment) | stable releases |
| `WDOS_STABLE_MINISIGN_PASSWORD` | password chosen at key-gen time | stable releases |

### Recommended: gate stable behind a GH environment

Add a GH Actions **environment** called `stable-release` and put the two `WDOS_STABLE_*` secrets there (instead of at the repo/org level directly). Configure the environment to require manual reviewer approval. Then in any consumer repo, the stable workflow won't even be able to read the secret without explicit human approval — restoring most of the offline-key safety property.

Consumer wrapper for stable becomes:

```yaml
jobs:
  release:
    uses: MicropleDev/.github/.github/workflows/go-release.yml@main
    with: { binary_name: heisenberg, version_pkg: heisenberg/pkg/version, build_path: ., bump_type: ${{ inputs.bump_type }} }
    secrets: inherit
    # environment: stable-release  # uncomment if W8 is updated to take environment as input
```

(The composite action and reusable workflow as currently authored leave environment selection to the caller; we'd add it as a workflow input if/when the protection actually fires.)

## Consumer usage — `secrets: inherit`

Caller workflows must opt in to passing secrets through to reusable workflows. The standard form:

```yaml
# .github/workflows/dev-release.yml in a consumer repo (heisenberg, etc.)
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

If `secrets: inherit` is omitted, the sign step fails fast with a clear error pointing at the missing secret.

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
