# Fork divergence

This repository is a fork of [home-assistant/iOS](https://github.com/home-assistant/iOS).

**Fork point:** `9b4da789` — *Fix lock screen circular widgets (#5561)*, 2026-08-29.

Upstream commits are picked manually rather than merged, so every difference from upstream has to
be deliberate and recorded here. A difference that is not on this list is either a mistake or an
undocumented decision — both are worth investigating rather than preserving.

The companion Android fork keeps the same discipline in
`woow_ha_app/docs/fork-divergence.md`; this file follows its format.

## How to check divergence for a file

```bash
# one-time: a local clone of upstream
git clone https://github.com/home-assistant/iOS.git ~/ha-ios-upstream

cd ~/ha-ios-upstream && git fetch origin
diff <(git show origin/main:<path>) <path-in-this-repo>
```

## Intentional divergence

### Toolchain compatibility

| File / area | Difference | Why | Upstream status |
|---|---|---|---|
| `Sources/HAWatchComplications/Sources/RectangularProgressView.swift` | `CGFloat(clamped)` anchors the thumb position expression (commit `2cd4555e`) | Swift 6.2.4 (Xcode 26.3) rejects the mixed CGFloat/Double expression as an ambiguous use of `/`; upstream CI on Xcode 26.4 accepts it. No behavior change | **Upstream compiles only because it uses a newer Xcode** — candidate for an upstream PR; drop on rebase once upstream pins ≥ 26.4 semantics |

### Brand and edition infrastructure (PRD Phase 0, 2026-08-30)

Implemented per `docs/plans/2026-08-29-prd-woowtech-ios-port.md`. All fork-only, never upstreamed.

| File / area | Difference | Why | Upstream status |
|---|---|---|---|
| `Configuration/HomeAssistant.xcconfig` | `BUNDLE_ID_PREFIX = com.woowtech`; new `WOOW_PRODUCT_BASE = home`, `WOOW_DISPLAY_NAME = woowtech Home`; `PRODUCT_BUNDLE_IDENTIFIER` formula uses `$(WOOW_PRODUCT_BASE)` instead of the literal `HomeAssistant` | Fork identity (`com.woowtech.home` / `com.woowtech.homecloud`, PRD D2) with a single overridable variable per edition | Permanent — re-apply on rebase |
| `Configuration/WoowtechCloud.xcconfig` | New file: `WOOW_PRODUCT_BASE = homecloud`, `WOOW_DISPLAY_NAME = woowtech Home Cloud`, adds `CLOUD_EDITION` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | Cloud edition overrides, passed via `xcodebuild -xcconfig` only; deliberately not referenced by `project.pbxproj` so the on-prem build is unchanged | Fork-only new file — survives rebase untouched |
| `HomeAssistant.xcodeproj/project.pbxproj` | 4 lines: the two hardcoded WatchWidgets bundle ids become `"$(BUNDLE_ID_PREFIX).$(WOOW_PRODUCT_BASE)$(BUNDLE_ID_SUFFIX).watchkitapp.WatchWidgets"`; the two `HomeAssistant-WatchAppTests` ids become `"$(BUNDLE_ID_PREFIX).$(WOOW_PRODUCT_BASE)-WatchAppTests"` | These were the only `PRODUCT_BUNDLE_IDENTIFIER` values not derived from the xcconfig formula (everything else composes via `PROVISIONING_SUFFIX`) | Re-apply on rebase — pbxproj is a conflict hotspot; the change is a pure 4-line string substitution |
| `Sources/App/Resources/Info.plist` | `CFBundleDisplayName`: `$(PRODUCT_NAME)` → `$(WOOW_DISPLAY_NAME)` | Home-screen name per edition; `PRODUCT_NAME` stays upstream's `HomeAssistant-$(TARGET_NAME)` for crash-log sorting | Re-apply on rebase |
| `Sources/WatchApp/Info.plist`, `Sources/Extensions/Share/Resources/Info.plist` | `CFBundleDisplayName`: literal `Home Assistant` → `$(WOOW_DISPLAY_NAME)` | Same | Re-apply on rebase |
| `Configuration/Entitlements/*.entitlements` (6 files) | App group `group.$(BUNDLE_ID_PREFIX).homeassistant$(BUNDLE_ID_SUFFIX)` → `group.$(BUNDLE_ID_PREFIX).$(WOOW_PRODUCT_BASE)$(BUNDLE_ID_SUFFIX)` | Upstream already uses build-setting expansion here; the new value matches the code-side `AppConstants.AppGroupID` (`"group." + BundleID.lowercased()` — `home`/`homecloud` are already lowercase, so the two derivations agree for both editions, unlike upstream where `homeassistant` is the pre-lowercased spelling of `HomeAssistant`) | Re-apply on rebase. **Simulator builds do not validate entitlements** (`CODE_SIGNING_ALLOWED=NO`); real-device verification of the app group waits on the WOOWTECH Apple Developer Team (open decision O5) |
| `Sources/Shared/Notifications/LocalPush/LocalPushEvent.swift` | `"app_id": "io.robbie.HomeAssistant"` → `AppConstants.BundleID` | The hardcode would leak upstream's identity in local-push registration info; `AppConstants` is in the same module and `BundleID` strips the `.PushProvider` suffix, so the swap is painless. Minor semantic delta vs upstream: debug builds now report the `.dev` id instead of the release id | Arguably an upstream bug (hardcode vs derived id); candidate for an upstream PR |
| `.github/workflows/` — `download_localized_strings.yml`, `auto_delete_unused_strings.yml`, `delete_lokalise_keys.yml`, `distribute.yml`, `push_deploy.yml`, `release_macos.yml` | Job-level `if: github.repository == 'home-assistant/iOS'` | Lokalise sync and external publish/deploy jobs must never fire from this fork (Lokalise nightly would also wash fork strings out of `Localizable.strings`); job-level guard is the minimal diff. `auto_delete_unused_strings.yml` gates `detect`, which transitively skips its `delete` job; `delete_lokalise_keys.yml` gates `delete_keys`, which transitively skips `open_cleanup_pr` | Re-apply on rebase; compare against upstream on every workflow change |
| `Tools/build-both-editions.sh` | New file: builds onprem then cloud (Debug, simulator), exits non-zero on first failure | Cloud-only code compiles only under `CLOUD_EDITION` — without a dual build the other edition rots silently (PRD §1) | Fork-local tooling |
| `docs/plans/`, `docs/fork-divergence.md` | Fork planning docs and this file | — | Fork-only |

## Deliberately NOT diverged

- **`Sources/Shared/Environment/CrashReporter.swift`** is kept byte-identical to upstream. Its
  `setup()` guards on `AppConstants.BundleID.starts(with: "io.robbie.")`, so after the bundle id
  change the (already no-op) crash reporter/analytics path disables itself automatically. That is
  the accepted behavior for this fork — do not "fix" the prefix check.
- **`PRODUCT_NAME = HomeAssistant-$(TARGET_NAME)`** stays upstream. Only the user-visible
  `CFBundleDisplayName` is rebranded; the executable name keeps upstream's crash-log-friendly shape
  and avoiding the rename keeps the pbxproj diff at zero for this setting.
- **`AppConstants.BundleID` suffix-strip list** is untouched: it strips known target suffixes
  regardless of prefix, and none of the strip strings occur inside `com.woowtech.home[.dev]` or
  `com.woowtech.homecloud[.dev]`, so `AppGroupID` derivation is self-consistent for both editions
  without modification.

## Known notes (not divergence)

- Simulator builds (`CODE_SIGNING_ALLOWED=NO`) neither sign nor validate entitlements, so the app
  group rename above is compile-verified only. On-device validation, push, CarPlay and Thread
  entitlements all wait on the WOOWTECH Apple Developer Team / provisioning (PRD open decision O5).
- Remote push is expected to be dead under the new bundle id (upstream's push server is tied to
  `io.robbie.HomeAssistant` and Home Assistant's APNs certificate) — PRD open decision O1, not a
  Phase 0 regression.
