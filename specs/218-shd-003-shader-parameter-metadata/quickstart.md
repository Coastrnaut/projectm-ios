# Quickstart: SHD-003 validation

```bash
cd <worktree>
# Package (host + host GPU): metadata, catalog, GPU golden
swift test --package-path Packages/Compositor --filter 'ShaderParameterMetadataTests|ProceduralMaterialsTests'
# Linux shape
swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
# App unit + UI test on "SHD3 iPhone 17" (iOS 27.2)
xcodegen generate
xcodebuild build-for-testing -scheme projectM-iOS -destination 'platform=iOS Simulator,name=SHD3 iPhone 17' ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/MaterialInspectorTests -only-testing:projectM-iOSUITests/MaterialInspectorUITests
```

Expected: all pass; the UI test shows `materialControl.material.plasma.scale` with label "Scale (waves across the
shorter side)" and value "2.00", disabled. Device (`{device}`): open the seeded material layer on D1 and read
the controls with VoiceOver.
