# Quickstart: UIX-014 Offline Help Browser

Prerequisites: the worktree with `Build` linked and the preset submodules, `xcodegen generate`, simulator
"UIX14 iPhone 17" (iOS 27.2).

1. Unit tests: `xcodebuild build-for-testing` then `test-without-building -only-testing:projectM-iOSTests/HelpLibraryTests`.
   Expect every content rule of `contracts/help-content.md` to pass and every article to open through the model.
2. UI test: `-only-testing:projectM-iOSUITests/HelpBrowserUITests` (under 30 s). Opens Settings › Help, searches
   "midi" and "flash", opens two articles and checks their headings.
3. Network scan: `python3 scripts/check_network_symbols.py <DerivedData>/Build/Products/Debug-iphonesimulator/projectM-iOS.app`
   → passes; `python3 scripts/check_compliance.py` → OK.
4. `{device}` (UIX-014-T12): on D1 turn on Airplane Mode (Wi-Fi off too), open Settings › Help and open all eleven
   articles; each shows its title and text at once.
