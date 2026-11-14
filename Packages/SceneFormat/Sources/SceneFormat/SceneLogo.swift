// SceneLogo.swift — the MED-010 logo in a scene (MED-010-R10; research MED-010-D6; contracts/logo-overlay.md C5).
//
// Stored as an asset of type `logo`: `{"type": "logo", "storeID": "<UUID>", "placement": {…}}`. The type is
// new, so apps without MED-010 keep the whole asset verbatim as an unknown asset (SCN-001-R10); no version
// change. `placement` is read leniently through `LogoPlacement(dictionary:)`: a missing or malformed field
// reads as its default and numbers are clamped; a placement that is not an object reads as the default.
// A scene's logo is its first `logo` asset in key order (the app writes one, under the key `logo`).
import Compositor
import ImageLayer

extension SceneAsset {
    public static let logoPlacementKey = "placement"

    /// A logo asset with its placement.
    public static func logo(storeID: String, placement: LogoPlacement) -> SceneAsset {
        var asset = SceneAsset(.logo(storeID: storeID))
        asset.logoPlacement = placement
        return asset
    }

    /// MED-010: the placement of a `logo` asset (nil for other kinds; the default when absent or malformed).
    public var logoPlacement: LogoPlacement? {
        get {
            guard case .logo = kind else { return nil }
            guard let o = extra[Self.logoPlacementKey]?.objectValue else { return .default }
            var plain: [String: Any] = [:]
            for (key, value) in o {
                switch value {
                case let .string(text): plain[key] = text
                case let .number(n): if let d = n.doubleValue { plain[key] = d }
                default: break
                }
            }
            return LogoPlacement(dictionary: plain)
        }
        set {
            guard case .logo = kind else { return }
            guard let p = newValue else { extra[Self.logoPlacementKey] = nil; return }
            let values: [String: SceneJSON] = [
                "corner": .string(p.corner.rawValue), "anchorX": .double(p.customAnchor.x), "anchorY": .double(p.customAnchor.y),
                "size": .double(p.size), "margin": .double(p.margin), "opacity": .double(p.opacity),
            ]
            extra[Self.logoPlacementKey] = .object(values)
        }
    }
}

/// The scene's logo: asset key, store identifier and placement.
public struct SceneLogo: Sendable, Equatable {
    public static let assetKey = "logo"

    public var key: String
    public var storeID: String
    public var placement: LogoPlacement

    public init(key: String = SceneLogo.assetKey, storeID: String, placement: LogoPlacement) {
        self.key = key
        self.storeID = storeID
        self.placement = placement
    }
}

extension SceneDocument {
    /// MED-010: the first `logo` asset by key (nil: the scene records no logo).
    public var logo: SceneLogo? {
        for key in assets.keys.sorted(by: SceneJSONWriter.utf8Precedes) {
            guard let asset = assets[key], case let .logo(storeID) = asset.kind else { continue }
            return SceneLogo(key: key, storeID: storeID, placement: asset.logoPlacement ?? .default)
        }
        return nil
    }
}
