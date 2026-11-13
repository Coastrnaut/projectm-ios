---
name: no-simulator-panel-prompts
description: Agents must not use the iOS Simulator panel tool (attach prompts interrupt the owner); test headless only
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-13T16:59:05.937Z
---

On 2026-11-13 the owner asked whether they had to keep clicking "attach" / "allow" on simulator prompts
during the autonomous run. They do not: all evidence comes from headless `xcodebuild`, `xcrun simctl`
and XCUITest. The prompts came from feature agents calling the iOS Simulator panel tool
(`mcp__Claude_Code_iOS_Simulator__control`), which asks the owner for device access each time.

**Why:** the prompts interrupt the owner for no benefit; the owner wants little human interaction
([[best-judgement-on-choices]]).

**How to apply:** every agent brief says not to call the Simulator panel tool (no attach, screenshot
or launch through it); use `simctl io <udid> screenshot` when a picture is needed. Only open the
panel when the owner explicitly asks to watch the app.
