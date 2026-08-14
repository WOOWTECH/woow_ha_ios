# apporo iOS 種入與換裝就緒清單

前提:simon 全流程綠(已於 2026-08-15 達成模擬器驗證;實機驗收見 simon repo)。

## 流程(與 simon 完全相同)

1. **從基底 repo 種入**(絕不從 simon 目錄種——換裝過的 code 關鍵字比對不到):

   ```bash
   cd ~/Desktop && git clone woow_ha_ios Woow_apporo_ha_ios   # 或 GitHub 上的基底 repo
   cd Woow_apporo_ha_ios && git remote rename origin base-local
   git rm -rq .github/workflows && git commit -m "ci: disable all upstream workflows"
   git tag pre-rebrand
   ```

2. **建 `Tools/brand/apporo-ios.conf`**(參照 `simon-ios.conf`),需備妥:
   - [ ] `LOGO_SRC`:1024×1024 PNG。**apporo logo 需先處理 alpha/白底**(Apple 拒 alpha;
     `icon_tool.swift` 會壓平到 `ICON_BG`,但 logo 本身若設計預期白底要先確認 `ICON_BG` 顏色)
   - [ ] `OAUTH_CLIENT_ID`:apporo 的 client_id 頁(需已宣告 `<apporo-scheme>://auth-callback`,
     照 Android 慣例放 `woowtech.github.io/Woow_apporo_ha_app/...`)。**頁面先上線再換裝**,
     否則 OAuth 全斷(IndieAuth 驗證,見 rebrand-inventory.md §3)
   - [ ] `URL_SCHEME` / `BUNDLE_ID_PREFIX` / `BUNDLE_ID_BASE` / `BRAND_HOST` / `PRIMARY_COLOR`

3. **執行**:

   ```bash
   bash Tools/brand/rebrand-ios.sh Tools/brand/apporo-ios.conf
   python3 Tools/brand/preflight-ios.py Tools/brand/apporo-ios.conf
   pod install
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
     -workspace HomeAssistant.xcworkspace -scheme App-Debug \
     -destination 'platform=iOS Simulator,name=iPhone 17' build
   git add -A && git commit -m "rebrand: apply apporo branding"
   ```

4. 產出 §6.5 矩陣 after 表歸檔(參照 simon `docs/bundle-id-matrix.md` 的指令)。

## 本機環境需求(simon 期已踩平的雷)

- Xcode 26.6+、watchOS platform 已下載(否則 scheme 驗證擋編譯)
- CocoaPods 用 brew 版(`brew install cocoapods`)+ 手動裝 plugin:
  `GEM_HOME=/opt/homebrew/Cellar/cocoapods/<ver>/libexec gem install cocoapods-acknowledgements`
  (rbenv ruby 3.1.2 在 Xcode 26 clang 下編不起來,不要走 bundler)
- `brew install swiftlint swiftformat`(Codegen 的 lint build phase 硬需求)
- 所有 xcodebuild/simctl 帶 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- 模擬器用 iPhone 17(無 iPhone 16)

## 已知一次性腳本紀律

- 重跑無效;改參數 → `git reset --hard pre-rebrand` 再跑
- 換裝後 `pod install` 必跑(PRODUCT_NAME 變更)
- preflight fail 即擋 commit,全綠才算完成
