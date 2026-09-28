# Release signing

WatchDog OS release artifacts are signed with [minisign](https://jedisct1.github.io/minisign/) (Ed25519). Public keys are committed to [`MicropleDev/watchdog-os/manifest/keys/`](https://github.com/MicropleDev/watchdog-os/tree/main/manifest/keys); secret keys live in the storage locations described below.

## Keys: one signing key per channel, a trusted key SET per channel

CI signs each channel with **one** key: the org secret for that channel. Devices trust an ordered **set** of keys per channel (MicropleDev/pinkman#47): the primary, an offline standby and, during a transition, a retiring key. The full inventory and the rotation runbook are in [`watchdog-os/manifest/keys/README.md`](https://github.com/MicropleDev/watchdog-os/blob/main/manifest/keys/README.md). That file is the source of truth; this table only summarises it.

| Channel | Key (file in `manifest/keys/`) | Id | Role | Secret |
|---|---|---|---|---|
| `stable` | `wdos-stable.pub` | `3A77F5DD20A6A5C2` | primary: signs manual stable cuts via `go-release.yml` | Apple Passwords, group "Microple Keys". Staged as `WDOS_STABLE_MINISIGN_KEY`/`_PASSWORD`. Rotated 2026-08-02 (prev `01FB8B9873285A05`, password lost; never used in production). |
| `stable` | `wdos-stable-standby.pub` | `FCE32A819F5618B3` | standby | Apple Passwords only. Never a GitHub secret. |
| `dev` | `wdos-dev.pub` | `6C6B47171265AD45` | primary: takes over signing when the transition switches the org secret | Apple Passwords, entry "WDOS minisign wdos-dev". |
| `dev` | `wdos-dev-standby.pub` | `6E8DA2A7D50BCAC3` | standby | Apple Passwords only. Never a GitHub secret. |
| `dev` | `wdos-dev-legacy.pub` | `0A08F649ED6E0F74` | **retiring**: CI signs every dev cut with it today | Org secret `WDOS_DEV_MINISIGN_KEY`/`_PASSWORD` **only**. No offline copy. |

The Pi-side OTA agent (`wd-updater`) compiles these sets in. It accepts a signature only from a key in the **device's own channel** set, choosing the key by the signature's key id, and fails closed on anything else. The sets are disjoint, so a compromised dev key (primary, standby or retiring) cannot ship a fake stable. A standby protects against a **lost** secret, not a **leaked** one: a leaked key stays trusted until an agent without it reaches every device.

## Secret storage details

The two channels deliberately use different storage scopes — different threat models for each.

### Dev secrets — org-level (no gating)

Add at **Org Settings → Secrets and variables → Actions** on the `MicropleDev` org:

| Name | Value |
|---|---|
| `WDOS_DEV_MINISIGN_KEY` | full secret-key text of the channel's signing key: the Notes of its Apple Passwords entry (during the pinkman#47 transition this is still the retiring `0A08F649ED6E0F74`, which has no offline copy) |
| `WDOS_DEV_MINISIGN_PASSWORD` | that key's passphrase: the Password of the same entry |

Visibility: "All repositories" (or restrict to the Go service repos). Dev cuts fire on every push to main — gating them would defeat the auto-cadence.

### Stable secrets — per-repo environment, required-reviewer approval

Stable cuts are deliberate and infrequent; the secrets should require a human click before they're accessible.

In **each consumer repo** (heisenberg, weather-server, sports-server, gustavo — the four Go services), under **Settings → Environments → New environment**:

1. Name the environment `stable-release` (the consumer's wrapper passes this as the `environment` input — see below).
2. Configure **Required reviewers** = `mavis-dev` (or whoever should approve stable cuts).
3. Add the two secrets inside that environment:

| Name | Value |
|---|---|
| `WDOS_STABLE_MINISIGN_KEY` | full secret-key text of `wdos-stable` (Notes of its Apple Passwords entry, "Microple Keys") |
| `WDOS_STABLE_MINISIGN_PASSWORD` | its passphrase (Password of the same entry) |

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

`minisign -V` takes one public key. Try the **channel's** keys in turn. The signature names its key id, so exactly one key can match:

```bash
# minisign expects the signature alongside the file (<file>.minisig); use -x to point elsewhere
f=watchdog-bundle-0.1.1-dev.20260618.abc1234.tar.zst
for k in manifest/keys/wdos-dev*.pub; do        # stable artifact: manifest/keys/wdos-stable*.pub
  minisign -Vm "$f" -p "$k" -q && echo "verified by $k" && break
done
```

If nothing prints "verified by", reject the artifact.

To check what a **shipped** `wd-updater` trusts, run `wd-updater --version` on the device. It prints one `trusted keys <channel>: …` line per channel. From a host, run `strings wd-updater-*-linux-arm64 | grep -o 'minisign public key [0-9A-F]*'`.

## Key rotation

The executable procedures live in [`watchdog-os/manifest/keys/README.md`](https://github.com/MicropleDev/watchdog-os/blob/main/manifest/keys/README.md#key-procedures): planned rotation, lost secret (sign with the standby) and leaked secret. The one rule every procedure follows: **the bundle that delivers a new trust set is verified by the old set.** So:

1. Add the new `.pub` to pinkman `pkg/trust/keys/` (with its trust-set slot) **and** to `watchdog-os/manifest/keys/`, byte-identical. Pinkman goes first; watchdog-os's `trust-keys` workflow checks the parity.
2. Ship that `wd-updater`, signed with a key devices **already** trust. Confirm `wd-updater --version` on every device.
3. Only then point the channel's Actions secret at the new key. Switching the secret before step 2 is confirmed makes every device on an older agent reject every update, including the one that would fix it. Those devices can then only be recovered by reflashing.
4. Drop the retired key from both repos in a later release.

There is no `/etc/wd-updater/trusted-keys/` directory and no provisioning-time key file. Keys are compiled into `wd-updater`.

The composite action itself is key-agnostic. It takes whatever `key`/`password` inputs you pass.

## Related issues

- [pinkman#47](https://github.com/MicropleDev/pinkman/issues/47) — multi-key trust per channel (standby keys, dev key transition)

- [watchdog-os#60](https://github.com/MicropleDev/watchdog-os/issues/60) — W7 (composite action + key policy)
- [watchdog-os#61](https://github.com/MicropleDev/watchdog-os/issues/61) — W8 (wire signing into all release workflows)
- [watchdog-os#52](https://github.com/MicropleDev/watchdog-os/issues/52) — OTA epic
