#!/usr/bin/env python3
"""Rebrand preflight — 換裝後全項驗證,fail 即擋 commit。

用法: preflight-ios.py Tools/brand/simon-ios.conf
"""
import glob
import json
import os
import re
import shlex
import subprocess
import sys

FAILS = []
PASSES = []


def check(name: str, cond: bool, detail: str = "") -> None:
    (PASSES if cond else FAILS).append(f"{name}{(' — ' + detail) if detail and not cond else ''}")


def read(path: str) -> str:
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def load_conf(path: str) -> dict:
    conf = {}
    for line in read(path).splitlines():
        line = line.split("#")[0].strip()
        if "=" in line:
            k, v = line.split("=", 1)
            conf[k.strip()] = shlex.split(v)[0] if v.strip() else ""
    return conf


def main() -> None:
    conf = load_conf(sys.argv[1])
    app, scheme = conf["APP_NAME"], conf["URL_SCHEME"]
    prefix, base = conf["BUNDLE_ID_PREFIX"], conf["BUNDLE_ID_BASE"]
    client = conf["OAUTH_CLIENT_ID"]
    color = conf["PRIMARY_COLOR"]

    # 1. xcconfig
    xcc = read("Configuration/HomeAssistant.xcconfig")
    check("xcconfig BUNDLE_ID_PREFIX", f"BUNDLE_ID_PREFIX = {prefix}" in xcc)
    check("xcconfig BRAND_BUNDLE_BASE 拼接", "$(BRAND_BUNDLE_BASE)" in xcc)
    check("xcconfig 無 io.robbie 殘留", "io.robbie" not in xcc)
    check("Brand.xcconfig 存在", os.path.exists("Configuration/Brand.xcconfig"))

    # 2. OAuth 三常數
    oad = read("Sources/App/Onboarding/API/OnboardingAuthDetails.swift")
    check("OAuth clientID", client in oad and "home-assistant.io/iOS" not in oad)
    check("OAuth redirectURI", f"{scheme}://auth-callback" in oad and "homeassistant://" not in oad)
    check("OAuth scheme", f'scheme = "{scheme}"' in oad)
    atr = read("Sources/Shared/API/Authentication/AuthenticationRoutes.swift")
    check("AuthenticationRoutes clientID", client in atr and "home-assistant.io/iOS" not in atr)

    # 3. URL scheme 全域殘留(排除白名單: 協定 key / fixtures / vendored)
    r = subprocess.run(
        ["grep", "-rln", "--include=*.swift", "homeassistant://", "Sources/", "Tests/"],
        capture_output=True, text=True)
    leftovers = [l for l in r.stdout.splitlines() if "deviceregistry" not in l]
    check("Sources/Tests 無 homeassistant:// 殘留", not leftovers, str(leftovers[:5]))

    # 4. pbxproj
    pbx = read("HomeAssistant.xcodeproj/project.pbxproj")
    check("ENV_URL_HANDLER 已換", f'ENV_URL_HANDLER = "{scheme}"' in pbx or f"ENV_URL_HANDLER = {scheme}" in pbx)
    check("ENV_URL_HANDLER 無殘留",
          not any("homeassistant" in m.lower() for m in re.findall(r"ENV_URL_HANDLER = \"?([\w-]+)\"?;", pbx)))
    check("ENTITLEMENTS_VARIANT 佈線", "$(ENTITLEMENTS_VARIANT)" in pbx)
    check("CODE_SIGN_ENTITLEMENTS 全數改道(含 catalyst 引號形態)",
          not re.search(r'CODE_SIGN_ENTITLEMENTS[^=]*= "?Configuration/Entitlements/[A-Za-z-]+\.entitlements', pbx))
    check("PRODUCT_NAME 無 Home Assistant", 'PRODUCT_NAME = "Home Assistant' not in pbx and "PRODUCT_NAME = HomeAssistant;" not in pbx)
    check("TEST_HOST 無舊 app 名", "Home Assistant Δ.app" not in pbx)

    # 5. entitlements
    for f in glob.glob("Configuration/Entitlements/**/*.entitlements", recursive=True):
        t = read(f)
        check(f"entitlements 無舊拼接 {f}", ".homeassistant$" not in t.lower().replace("(bundle_id_suffix)", "$"))
        check(f"entitlements 無 io.robbie {f}", "io.robbie" not in t)
    dev_app = read("Configuration/Entitlements/dev/App-ios.entitlements")
    for k in ("aps-environment", "associated-domains", "nfc", "siri"):
        check(f"dev 精簡版已拔 {k}", k not in dev_app)
    rel_app = read("Configuration/Entitlements/release/App-ios.entitlements")
    check("release 完整版 applinks → 品牌網域", conf["BRAND_HOST"] in rel_app and "home-assistant.io" not in rel_app)
    for cfg, want in (("debug", "dev"), ("release", "release")):
        check(f"{cfg}.xcconfig ENTITLEMENTS_VARIANT={want}",
              f"ENTITLEMENTS_VARIANT = {want}" in read(f"Configuration/HomeAssistant.{cfg}.xcconfig"))

    # 6. 字串
    r = subprocess.run(["grep", "-c", "Home Assistant", "Sources/App/Resources/en.lproj/Localizable.strings"],
                       capture_output=True, text=True)
    n = int(r.stdout.strip() or 0)
    check("en Localizable 品牌殘留 ≤ 白名單量(≤3)", n <= 3, f"還有 {n} 條")
    r = subprocess.run(["grep", "-c", "Home Assistant", "Sources/App/Resources/zh-Hant.lproj/Localizable.strings"],
                       capture_output=True, text=True)
    n = int(r.stdout.strip() or 0)
    check("zh-Hant Localizable 品牌殘留 ≤ 3", n <= 3, f"還有 {n} 條")

    # 7. icon: 1024 無 alpha
    ic = "Sources/App/Resources/Assets.xcassets/AppIcon.appiconset"
    with open(os.path.join(ic, "Contents.json")) as f:
        entries = [e for e in json.load(f)["images"] if e.get("filename")]
    check("AppIcon 有檔案項", bool(entries))
    if entries:
        f0 = os.path.join(ic, entries[0]["filename"])
        r = subprocess.run(["sips", "-g", "hasAlpha", f0], capture_output=True, text=True)
        check("AppIcon 主圖無 alpha", "hasAlpha: no" in r.stdout, r.stdout.strip())

    # 8. AccentColor
    ac = read("Sources/App/Resources/Assets.xcassets/accentColor.colorset/Contents.json")
    check("accentColor = 品牌色", f"0x{color[2:4].upper()}" in ac and f"0x{color[4:6].upper()}" in ac and "0x9A" not in ac)
    check("haPrimary = 品牌色", "0x9A" not in read("Sources/Shared/Assets/Colors.xcassets/haPrimary.colorset/Contents.json"))
    check("brandBlue swift", "0x18BCF2" not in read("Sources/Shared/DesignSystem/BaseColors.swift").upper())
    check("Widgets AccentColor 存在", os.path.exists("Sources/Extensions/Widgets/Resources/Assets.xcassets/AccentColor.colorset/Contents.json"))

    # 9. 顯示名
    for p in ("Sources/WatchApp/Info.plist", "Sources/Extensions/Share/Resources/Info.plist"):
        check(f"顯示名 {p}", app in read(p) and ">Home Assistant<" not in read(p))

    # 10. 授權合規
    check("LICENSE.md 保留", os.path.exists("LICENSE.md"))

    # 11. CI 安全網(決策 13;種入 commit 應已拔除)
    check("Lokalise cron workflow 已移除",
          not os.path.exists(".github/workflows/download_localized_strings.yml"))

    # 12. 入口連結殘留(§8;stun./mobile-apps./my./demo 為刻意保留)
    r = subprocess.run(["grep", "-rln", "--include=*.swift",
                        "-e", "companion.home-assistant.io", "-e", "alerts.home-assistant.io",
                        "Sources/"], capture_output=True, text=True)
    left = [l for l in r.stdout.splitlines()
            if "WebViewExternalBusMessage" not in l and "WhatsNewCatalog" not in l
            and "ConnectionInfo+WebView" not in l and "PushServer" not in l]
    check("無 companion/alerts.home-assistant.io 入口殘留", not left, str(left[:5]))

    print("\n=== preflight 結果 ===")
    for p in PASSES:
        print(f"  ✓ {p}")
    if FAILS:
        print(f"\n  ✗ FAIL {len(FAILS)} 項:")
        for f in FAILS:
            print(f"  ✗ {f}")
        sys.exit(1)
    print(f"\n全數通過({len(PASSES)} 項)")


if __name__ == "__main__":
    main()
