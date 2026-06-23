# MicropleDev naming conventions

How we name repos, services, packages, and binaries across the WatchDog
fleet. Locked 2026-06-23 alongside the OTA Phase 0 / new-repo wave; new
components MUST follow these, existing ones are grandfathered where
called out below.

The goal is to make repo lists scannable: looking at a name alone, you
should know what kind of thing it is and roughly where it runs.

## The five buckets

| Bucket | Pattern | What it means | Examples |
|---|---|---|---|
| **UI app** (Flutter, user-facing) | `{verb}dog` | A Flutter app the human looks at on the Pi screen | [setupdog](https://github.com/MicropleDev/setup-dog), [watchdog](https://github.com/MicropleDev/watchdog), [updatedog](https://github.com/MicropleDev/updatedog) |
| **Local service** (Pi-resident, headless) | random name (see below) | A daemon running on the Pi with no UI | [heisenberg](https://github.com/MicropleDev/heisenberg), [pinkman](https://github.com/MicropleDev/pinkman), [gustavo](https://github.com/MicropleDev/AlphaDog) (formerly `alphadog`) |
| **Cloud helper service** ("minion") | `watchdog-{role}-minion` | Cloud service that helps a device or user — auth, telemetry, broker. The `watchdog-` prefix is the fleet brand; minion-class services explicitly belong to a fleet. | watchdog-auth-minion |
| **Cloud data service** ("server") | `{feature}-server` | Cloud service that serves user-facing feature data | [weather-server](https://github.com/MicropleDev/weather-server), [sports-server](https://github.com/MicropleDev/sports-server) |
| **Flutter feature package** | `wd-{feature}` | Flutter package consumed by the UI apps; one repo per feature | [wd-weather](https://github.com/MicropleDev/wd-weather), [wd-sports](https://github.com/MicropleDev/wd-sports) |

### Why the split between `watchdog-*-minion` and `*-server`?

- `watchdog-{role}-minion` = **device-facing helpers** (watchdog-auth-minion
  brokers OAuth so the device never needs the client secret; future
  watchdog-telemetry-minion, etc.). Job is to *help the device do its thing.*
  Carries the `watchdog-` fleet prefix because minion-class services
  are inherently fleet-specific.
- `{feature}-server` = **user-facing data backends** (weather-server proxies
  WeatherAPI; sports-server caches football data). Job is to *answer
  user-content queries.* No fleet prefix — these are conceptually
  general-purpose data services that the watchdog fleet happens to be
  their first consumer.

When in doubt: if the response payload goes onto the Pi's display, it's
a `-server`. If the response payload helps the Pi talk to the rest of
the world, it's a `watchdog-*-minion`.

## Random names for local services — the Breaking Bad convention

Local services pick a **Breaking Bad character whose role in the show
roughly matches the service's role on the Pi.** This gives random-but-
memorable names without "what should we call this?" overhead.

| Service | Character | Why |
|---|---|---|
| heisenberg | Walter White / Heisenberg | The architect / kingpin — runs system control (WiFi, BT, brightness, volume, device identity) |
| pinkman | Jesse Pinkman | Heisenberg's partner-in-crime / implementer — applies the bundles heisenberg's world prescribes (the OTA updater agent) |
| gustavo | Gus Fring | The calm, methodical decider — picks which UI runs at boot (`setupdog-ui` or `watchdog-ui`); never panics, runs as root |

### Picking names for future services

When you spin up a new local service, look at its job description and
match a BB character whose role rhymes:

| Future role | Candidate |
|---|---|
| Cleanup / log rotation / "the janitor" | `mike` (the fixer) |
| Permission / sudoers / auth broker | `saul` (the legal guy) |
| Test / QA bot | `marie` (the obsessive watcher) |
| Quick-and-dirty stub | `todd` |
| Different cloud broker than minion | `hector` |

You don't have to pre-name these — the convention just means future
picks come quickly. **Reuse a name only if the role genuinely differs**
(don't run two `mike`s for the same kind of job).

## Grandfathered exceptions

| Name | What it is | Why it stays |
|---|---|---|
| **superdog** (+ `superdog-listener`) | Local services (LLM voice pipeline + wake-word) | Predates the convention. Deeply established — shipped binaries, install scripts, env templates, env vars in 5+ repos. Cost of rename is high for low gain. Reads as "random-ish dog name", close enough. |
| **SoundDog** / `wd_soundcloud` | Local audio service + Flutter package | Being decommissioned (feature dropped). No rename — just goes away. |
| **alphadog** | Local service (boot decider) | **Being renamed to `gustavo`** as a Phase 0 cleanup. Until that rename lands, refs to `alphadog` in install.sh / manifests are valid. |
| **setup-dog** | UI app (setup wizard) | **Being renamed to `setupdog`** — repo has a hyphen, convention is hyphen-less (`watchdog`, `updatedog`). Binary + Flutter package output already match the hyphen-less form (`setupdog-ui`). |
| **watchdog-os** | Pi OS bundle / installer repo | Not a service or UI — meta-repo for the bundle. The `-os` suffix is clearer than `wd-os`. Leave. |
| **dog-libs** | Shared Flutter packages umbrella | Meta-collection. Naming describes the *collection*, not the contents. Leave. |
| **dogserver** | Shared Go module (extracted from sports-server) | Meta-collection. Leave. |

> **Note:** `MicropleDev/wd-minions` was created as a planned Go-services umbrella but never developed past a scaffold. Being archived; pair-minion functionality landed in heisenberg / setup-dog / watchdog-auth-minion instead. The board's `wd-minions` Component option is being removed.

## Renaming an existing repo or component

GitHub auto-redirects old URLs forever after a rename. But for hygiene:

1. **Rename the repo** on GitHub (Settings → Repository name). 5 seconds.
2. **`grep` all dependent repos** for the old name. Common hits: workflow
   `uses:` lines, pubspec.yaml `git: url:`, go.mod paths, install.sh /
   verify.sh / manifest references, README links.
3. **Coordinated PR per dependent repo** to swap references. No rush —
   the redirect covers anything you miss.
4. **Local clones:** `git remote set-url origin git@github.com:MicropleDev/<new>.git`.
5. **Binary install paths** (e.g. `/opt/alphadog/` → `/opt/gustavo/`) get
   updated in install.sh / manifest / systemd unit / env tpls in the
   same sweep PR. Greenfield → no on-disk migration needed.

The only hard cost is paths embedded in published bundle assets — those
ship forever with the old name. New bundles after the rename ship the
new name. Since the fleet is greenfield (no Pis running prior bundles),
this is currently free.

## When to add a new bucket

Don't. Five buckets cover the entire WatchDog architecture as designed
through Phase 4 of OTA. If you find yourself wanting a sixth, the new
thing is probably an instance of an existing bucket — rethink before
extending the scheme.

The one likely future extension: a **test rig / HIL controller repo**.
That's tooling, not a runtime component. Lives outside this scheme —
name it descriptively (e.g. `hil-runner`) and move on.
