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

### Cloud data layer (PRD Phase 1, 2026-08-30)

| File / area | Difference | Why | Upstream status |
|---|---|---|---|
| `Sources/Shared/API/WoowPaas/` (10 files), `Tests/Shared/Models/WoowPaas/` | New fork-only files, each wrapped whole in `#if CLOUD_EDITION`: device-flow client, repository, in-memory session, token classifier, polling engine and their tests | WOOW PaaS data layer (PRD §2); compiled only in the cloud configuration | Fork-only new files — survive rebase untouched |

### Cloud onboarding screens and hooks (PRD Phase 2, 2026-08-30)

New fork-only files (each wrapped whole in `#if CLOUD_EDITION`, all in
`Sources/App/Onboarding/Woowtech/`): `CloudChooserView.swift`, `CloudSignInView.swift`,
`CloudProvisionView.swift`, `DeviceFlowViewModel.swift` (also hosts the shared `WoowtechCloud`
session/repository instances), `WoowtechStrings.swift`. Plus the string tables
`Sources/App/Resources/{en,zh-Hant}.lproj/Woowtech.strings` (fork-owned table so Lokalise sync
can never wash the keys out of `Localizable.strings`; swiftgen config untouched) and the tests
`Tests/App/Auth/HookRollbackTests.swift`, `Tests/App/Onboarding/CloudEditionNavigationTests.swift`.

Changes to shared files — the complete list of `#if CLOUD_EDITION` sites and edition hooks:

| File / area | Difference | Why | Upstream status |
|---|---|---|---|
| `Sources/App/Onboarding/Container/OnboardingNavigationView.swift` | **Hook 1**: `OnboardingNavigation.rootScreen(for:isCloudEdition:)` + `isCloudEdition` (the 5-line `#if` at line 53 is the edition question); the root switch maps `.cloudChooser` to `CloudChooserView` under a second `#if` (line 117, with an unreachable on-prem fallback); `view(for:)` gains the three cloud destination cases under a third `#if` (line 170) | Cloud initial onboarding starts at the chooser; "local" pushes the unchanged upstream welcome. The `isCloudEdition` parameter keeps both branches testable from one build | Re-apply on rebase (3 `#if` blocks in this file) |
| `Sources/App/Onboarding/API/OnboardingDestination.swift` | 4 `#if CLOUD_EDITION` blocks (lines 17, 31, 53, 85): the `welcome` / `cloudSignIn` / `cloudProvision` cases, plus their arms in `isAuthFlowStep`, `==` and `hash(into:)` | The pre-work inventory found **4 exhaustive-switch expansion points for the enum itself plus 1 in `OnboardingNavigationView.view(for:)` — 5 total** (the PRD's "count, don't guess" item). `==` has a `default`, but explicit cases are still required for correct equality | Re-apply on rebase |
| `Sources/Shared/Environment/Environment.swift` | **Hook 2a**: `AppEnvironment.onServerRegistered: ((Server) async throws -> Void)?` (line 206), no `#if` — plain nil-by-default closure in both editions | The `Current`-based seam (PRD D7): single optional async closure instead of an observer protocol | Re-apply on rebase (candidate to keep tiny; 1 property + doc comment) |
| `Sources/App/Onboarding/API/OnboardingAuth.swift` | **Hook 2b**: a `.then` inserted in `authenticate` between the cached-API swap and `steps(.complete)` (line 60), bridging the closure with `Promise { seal in Task { do/catch } }`; no `#if` | Runs after `servers.add`, before success is declared, so a throwing observer lands in the existing `recover` → `undoConfigure` and rolls the registration back (Android `ServerRegisteredListener` semantics). Deliberately not fire-and-forget | Re-apply on rebase |
| `Sources/App/AppDelegate.swift` | **Hook 2c**: 1 `#if CLOUD_EDITION` block (line 104) inside `willFinishLaunchingWithOptions`, assigning `Current.onServerRegistered = { _ in await WoowtechCloud.session.clear() }` — placed inside the existing `prohibit_environment_assignment` swiftlint-disable region, no new disables | Cloud launch-time wiring; clearing the in-memory session cannot fail, and the closure stays non-throwing so it can never roll a finished registration back | Re-apply on rebase |
| `HomeAssistant.xcodeproj/project.pbxproj` | 5 lines added to the existing `PBXFileSystemSynchronizedBuildFileExceptionSet` `42FD0000000400510051FC9B` (target `Shared-iOS`): the `Woowtech/*.swift` files | `Sources/App/Onboarding` is a synchronized group compiled by **both** the App target and `Shared-iOS` (which wants only `API/Bonjour.swift`); every onboarding UI file upstream is on this same exception list, and without these entries the cloud configuration would compile the cloud views into `Shared-iOS`, where `OnboardingAuthPresenter` etc. do not exist. Mechanical, same pattern as the 51 existing entries — no file references were added by hand | Re-apply on rebase (or re-tick the checkboxes in Xcode's target membership UI) |

Running total of `#if CLOUD_EDITION` sites in shared (non-fork-only) files after Phase 2: **8**
(3 in `OnboardingNavigationView.swift`, 4 in `OnboardingDestination.swift`, 1 in
`AppDelegate.swift`). Hooks 2a/2b carry no `#if` at all — they compile identically in both
editions and are inert while the closure is nil.

The provision→registration hand-off adds no divergence beyond the above: `CloudProvisionView`
reuses the upstream `OnboardingServersListViewModel.selectInstance` path (the same one manual URL
entry uses), so login, device naming, permissions and completion are unchanged upstream code.

## Known notes (not divergence)

- Simulator builds (`CODE_SIGNING_ALLOWED=NO`) neither sign nor validate entitlements, so the app
  group rename above is compile-verified only. On-device validation, push, CarPlay and Thread
  entitlements all wait on the WOOWTECH Apple Developer Team / provisioning (PRD open decision O5).
- Remote push is expected to be dead under the new bundle id (upstream's push server is tied to
  `io.robbie.HomeAssistant` and Home Assistant's APNs certificate) — PRD open decision O1, not a
  Phase 0 regression.

### Lessons from verification (2026-08-30)

- **Bundle-id leftovers come in two shapes.** Literal `io.robbie.*` strings, and *formula-style*
  references (`$(BUNDLE_ID_PREFIX).HomeAssistant$(BUNDLE_ID_SUFFIX)`) that greps for the literal
  never catch. The second shape lived in `Sources/WatchApp/Info.plist`
  (`WKCompanionAppBundleIdentifier` — broke simulator install with "Unable to Install") and in the
  `keychain-access-groups` entry of all six entitlements files. Both shapes are now zero; any
  rebase that touches plists or entitlements must re-run both sweeps.
- **Upstream latent deadlock, not patched here.** `AppConstants.AppGroupContainer`
  (AppConstants.swift:257) logs through `Current` in its nil-container fallback. That fallback runs
  during `AppEnvironment.init()` when the app-group entitlement is missing, re-entering the
  `underlyingCurrent` global mid-initialization — a same-thread `dispatch_once` trap (SIGTRAP at
  bootstrap). Upstream never hits it because their entitlement always resolves. Practical rule:
  **never pass `CODE_SIGNING_ALLOWED=NO` to simulator *test* runs** (it strips entitlements and
  triggers the fallback); build-only lanes may keep it. Candidate for an upstream issue/PR.
