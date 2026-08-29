# PRD：woowtech 功能自 Android 移植至 iOS（地端／雲端 edition 分離）

日期：2026-08-29。狀態：待 Alan 核准後動工。

來源真相：`~/woow_ha_app`（Android fork，PR #7 `feature/cloud-edition`，已通過真機 E2E 驗證）。
基底：官方 `home-assistant/iOS` main @ `9b4da789`（2026-08-29），**乾淨 clone**，非老闆的
`WOOWTECH/woow_ha_ios` 工具鏈（Alan 指示；見 §7 與該工具鏈的關係）。

## 0. 決策記錄（2026-08-29，Alan）

| # | 決策 |
|---|---|
| D1 | 先做 local branch（`feature/woowtech-port`）；遠端 repo 之後再定 |
| D2 | 兩個 bundle id，照 Android：`com.woowtech.home`（onprem）／`com.woowtech.homecloud`（cloud） |
| D3 | icon 暫用上游（老闆工具鏈有 `woowtech-icon.png` 素材，正式化時可取用） |
| D4 | 品牌常數採納老闆 2026-08-16 定案：APP_NAME `woowtech Home`、品牌藍 `#6183FC`、URL scheme `woowhome`、HA OAuth client_id `https://woowtech.github.io/woow_ha_ios/ios` |
| D5 | 不做 runtime 功能開關 —— build-time 隔離已達成目的（Alan：非必要就不做） |
| D6 | PaaS 常數與 Android 完全一致：debug→`stg.woowtech.io`、release→`paas.woowtech.io`、client_id `woow-ha-app`、scopes `ha:provision workspace:read smarthome:read` |

## 1. Edition 分離機制（Android flavor 的 iOS 對應）

- 新增編譯旗標 `CLOUD_EDITION`（`SWIFT_ACTIVE_COMPILATION_CONDITIONS`；上游已有 `DEBUG`、
  `WIDGET_EXTENSION` 先例）。
- 兩組 xcconfig：`Configuration/Woowtech.xcconfig`（共用品牌常數）＋
  `WoowtechCloud.xcconfig`（加 `CLOUD_EDITION` 與 `BUNDLE_ID` 改為 homecloud）＋兩個 scheme。
- 雲端原始碼永遠在 target 內，但整個檔案體包在 `#if CLOUD_EDITION` —— onprem 二進位
  完全不含雲端碼（與 Android release dex 驗證同標準）。
- 上游 bundle id 公式 `${BUNDLE_ID_PREFIX}.HomeAssistant${BUNDLE_ID_SUFFIX}` 改為可整段
  覆寫（一行 divergence），得到 `com.woowtech.home[cloud]`。

## 2. 架構對照（Android → iOS）

| Android（已交付） | iOS 設計 | Pattern |
|---|---|---|
| `AndroidEditionFlavorConventionPlugin`（常數收納） | `Sources/Shared/Woowtech/WoowtechConfiguration.swift` 單一 namespace enum＋`Woowtech.xcconfig` | 統一 configuration 收納 |
| Hook 1 `editionStartDestination()` | `OnboardingNavigation.requiredOnboardingStyle` ~3 行 `#if CLOUD_EDITION` 分流 | 上游 diff 最小化 |
| Hook 2 `ServerRegisteredListener`（Hilt @Multibinds） | `ServerRegisteredObserver` protocol，經 `AppEnvironment`（`Current`）註冊；cloud edition 掛 session 清理 observer | Observer；走上游 World pattern |
| `:cloud-data`（WoowPaasService/Repository/SessionRepository/TokenErrorClassifier） | `Sources/Shared/API/WoowPaas/`：`WoowPaasClient`（URLSession async/await＋Codable `.convertFromSnakeCase`）、protocol＋impl、Keychain session 儲存 | Repository；仿上游 `HomeAssistantRESTClient` 慣例 |
| 三畫面 chooser/sign-in/provision | 三個 SwiftUI View＋ViewModel，掛進 `OnboardingDestination`＋`OnboardingAuthPresenter.path` | MVVM＋上游 NavigationStack |
| 註冊完成點 `activateServer` 後 | `OnboardingAuth.authenticate()` 的 `Current.servers.add(...)` 之後（~2 行 hook）。走這條路 Watch／CarPlay／8 個 extension 零改動（已驗證 onboarding 僅存在主 app target） | — |

## 3. Function 清單

**A. 品牌（onprem 基底）**：bundle id 公式覆寫＋3 處 hardcode（WatchWidgets×2、WatchAppTests）、
`AppConstants.BundleID` 後綴表、`CrashReporter.swift:21`（`io.robbie.` 前綴檢查→改為停用或改前綴）、
`LocalPushEvent.swift:55`、App Group entitlement、`PRODUCT_NAME`（pbxproj 2 處＋3 個 Info.plist
hardcode）、fork 專屬字串放獨立 `Woowtech.strings` 表（Lokalise nightly 同步會洗掉
`Localizable.strings`）、停用上游 Lokalise×3 與上架 workflows。

**B. 雲端功能（逐檔對應 Android `:cloud-data`＋`app/src/cloud`）**：Device Flow client
（device_authorization→token 輪詢→provision→status 輪詢）、`TokenErrorClassifier`／
`ProvisionStatus`／`TokenPollResult`／DTOs、Keychain session＋Hook 2 清理、三畫面 UI 含
denied→重新開始復原、409 既有實例處理。

**C. 不移植**：FailFast/StrictMode（Android 專屬）、`IS_FULL` 修正、full/minimal dimension、
runtime 開關（D5）。

## 4. 測試（沿用 Android 紀律）

- WoowPaas client/repository 單元測試（Swift Testing＋OHHTTPStubs）。
  **Fixture 鐵律通用：禁止手寫，直接複用 Android Layer 2 錄自真流量的同一批
  `paas-fixtures`**（一次錄製，兩平台共用）。
- Edition 起點測試（照上游 `Tests/App/Onboarding/OnboardingNavigationTests.swift` 模式）。
- E2E：模擬器手動打 prod 全流程（同 Android 2026-08-26 驗證）。

## 5. Phases

| Phase | 內容 | 出口條件 |
|---|---|---|
| 0 | PRD＋fork-divergence.md＋branding＋兩 scheme／xcconfig | 兩 edition 模擬器可跑、名稱與 bundle id 正確 |
| 1 | WoowPaas data layer＋單元測試 | 測試綠、fixture 來自錄製 |
| 2 | 三畫面＋兩個 hook | onprem 二進位驗證無雲端符號 |
| 3 | E2E 打 prod＋navigation 測試 | 開通到活的 HA 實例 |
| 4 | CI（macOS runner；public repo 免費）；簽章／上架另案（需 WOOWTECH Apple Developer Team） | PR gate 綠 |

## 6. 風險與前置

- **P-i1（環境，擋 build 驗證）**：本機 Xcode 16.4／iOS 18.6 runtime，但上游最新 main CI 用
  Xcode 26.4。最新 main 幾乎必定無法用 16.4 編譯 —— 需安裝 Xcode 26.x 才能本機驗證。
- **P-i2（簽章，僅擋上架）**：上游 `DEVELOPMENT_TEAM=QMQYCKL255` 與 26 個 provisioning
  profiles 皆不可用；模擬器開發不受影響。
- **P-i3（遠端 repo）**：D1 先 local；工作僅存於本機，儘早定 remote。
- Keychain service＝BundleID：bundle id 改名後舊資料自然隔離（全新 app，無遷移問題）。

## 7. 與老闆 white-label 工具鏈（WOOWTECH/woow_ha_ios）的關係

該工具鏈釘在 `release/2026.7.3`，做的是**純品牌重貼**（無雲端功能），產出 simon／apporo／
woowtech 三個品牌 repo。本移植從乾淨上游 main 打（Alan 指示），但刻意維持：

1. 品牌常數與其 `woowtech-ios.conf` 完全一致（D4）—— 不製造第二套品牌真相；
2. 雲端功能全在新檔案＋兩個 hook 各 ~3 行 —— 未來可以整包 patch 移植回該基底，
   讓 simon／apporo 也能長出雲端版，不與其拓撲打架。
