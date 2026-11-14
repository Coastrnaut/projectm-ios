// SceneDecoding.swift — bytes → scene document (SCN-001-R1 to R10; research SCN-001-D2, D3, D8;
// contract C1, C4).
//
// Order: size (before parsing) → bounded parse (depth, duplicate keys) → format and version →
// count limits (before typed decoding) → typed decoding. Typed decoding throws `malformed` for a
// wrong JSON type or a missing required field, clamps opacity and transform components (warning
// `valueClamped`), drops unknown fields of closed objects (warning `droppedField`) and keeps unknown
// fields of the document, layers, bindings and assets.
import Compositor
import ParameterGraph

/// A decoded document and the warnings decoding produced.
public struct SceneDecodeResult: Sendable {
    public let document: SceneDocument
    public let warnings: [SceneIssue]
    /// SCN-013: the migration that ran before typed decoding (`migrated` is false for a current file).
    public let migration: SceneMigrationRecord

    init(document: SceneDocument, warnings: [SceneIssue],
         migration: SceneMigrationRecord = .unchanged(version: SceneDocument.currentVersion)) {
        self.document = document
        self.warnings = warnings
        self.migration = migration
    }
}

extension SceneDocument {
    /// Reads canonical or hand-written scene bytes (contract C4), migrating an older format version with
    /// the app's chain first (SCN-013 contract M1).
    public static func decode(_ bytes: [UInt8]) throws(SceneDecodeError) -> SceneDecodeResult {
        try decode(bytes, migrator: .standard)
    }

    /// `decode` with another migration chain (tests use synthetic chains; SCN-013-R6).
    public static func decode(_ bytes: [UInt8], migrator: SceneMigrator) throws(SceneDecodeError) -> SceneDecodeResult {
        guard !bytes.isEmpty else { throw .empty }
        guard bytes.count <= SceneLimits.maximumBytes else {
            throw .tooLarge(bytes: bytes.count, limit: SceneLimits.maximumBytes)
        }
        let parsed = try SceneJSONParser.parse(bytes, maximumDepth: SceneLimits.maximumDepth)
        let migrated: SceneMigrationResult
        do {
            migrated = try migrator.migrate(parsed)
        } catch {
            throw error.decodeError
        }
        var decoder = SceneDecoder()
        let document = try decoder.document(migrated.root)
        return SceneDecodeResult(document: document, warnings: decoder.warnings, migration: migrated.record)
    }
}

struct SceneDecoder {
    var warnings: [SceneIssue] = []

    // MARK: Document

    mutating func document(_ root: SceneJSON) throws(SceneDecodeError) -> SceneDocument {
        guard let o = root.objectValue, o["format"]?.stringValue == SceneDocument.formatName else { throw .notAScene }
        guard let versionValue = o["version"] else { throw .invalidVersion("nothing") }
        guard let number = versionValue.numberValue else { throw .invalidVersion(versionValue.typeName) }
        guard let version = number.int64Value, version >= 1 else { throw .invalidVersion(number.text) }
        guard version <= Int64(SceneDocument.currentVersion) else { throw .newerVersion(version) }
        try checkCounts(o)

        let root = "$"
        let id = try string(o, "id", root)
        let name = try string(o, "name", root)

        var layers: [SceneLayer] = []
        if let value = o["layers"] {
            let items = try array(value, ScenePath.key(root, "layers"))
            for (i, item) in items.enumerated() {
                layers.append(try layer(item, index: i, path: ScenePath.index(ScenePath.key(root, "layers"), i)))
            }
        }

        var parameters: [ParameterID: ParameterValue] = [:]
        if let value = o["parameters"] {
            let base = ScenePath.key(root, "parameters")
            for (key, item) in try object(value, base) {
                parameters[ParameterID(key)] = try parameterValue(item, ScenePath.key(base, key))
            }
        }

        var bindings: [SceneBinding] = []
        if let value = o["bindings"] {
            let base = ScenePath.key(root, "bindings")
            for (i, item) in try array(value, base).enumerated() {
                bindings.append(try binding(item, ScenePath.index(base, i)))
            }
        }

        var modulation = SceneModulation()
        if let value = o["modulation"] { modulation = try self.modulation(value, ScenePath.key(root, "modulation")) }

        var assets: [String: SceneAsset] = [:]
        if let value = o["assets"] {
            let base = ScenePath.key(root, "assets")
            for (key, item) in try object(value, base) {
                assets[key] = try asset(item, ScenePath.key(base, key))
            }
        }

        var groups: [SceneGroup] = []   // CMP-011
        if let value = o["groups"] {
            let base = ScenePath.key(root, "groups")
            for (i, item) in try array(value, base).enumerated() {
                groups.append(try group(item, ScenePath.index(base, i)))
            }
        }

        let known: Set<String> = ["format", "version", "id", "name", "layers", "parameters", "bindings", "modulation", "assets", "groups"]
        return SceneDocument(id: id, name: name, layers: layers, parameters: parameters, bindings: bindings,
                             modulation: modulation, assets: assets, groups: groups, extra: o.filter { (key: String, _: SceneJSON) -> Bool in !known.contains(key) })
    }

    /// Count limits, before any typed decoding (SCN-001-R8). Wrong types are left to typed decoding.
    private func checkCounts(_ o: [String: SceneJSON]) throws(SceneDecodeError) {
        func check(_ what: String, _ count: Int?, _ limit: Int) throws(SceneDecodeError) {
            if let count, count > limit { throw .tooMany(what: what, count: count, limit: limit) }
        }
        let layers = o["layers"]?.arrayValue
        try check("layers", layers?.count, SceneLimits.maximumLayers)
        try check("bindings", o["bindings"]?.arrayValue?.count, SceneLimits.maximumBindings)
        try check("parameter values", o["parameters"]?.objectValue?.count, SceneLimits.maximumParameterValues)
        try check("assets", o["assets"]?.objectValue?.count, SceneLimits.maximumAssets)
        for (i, layer) in (layers ?? []).enumerated() {
            try check("values in layer \(i)", layer.objectValue?["values"]?.objectValue?.count, SceneLimits.maximumValuesPerLayer)
        }
        let modulation = o["modulation"]?.objectValue
        try check("modulation generators", modulation?["generators"]?.arrayValue?.count, SceneLimits.maximumGenerators)
        try check("modulation connections", modulation?["connections"]?.arrayValue?.count, SceneLimits.maximumConnections)
        let groups = o["groups"]?.arrayValue   // CMP-011
        try check("groups", groups?.count, SceneLimits.maximumGroups)
        for (i, group) in (groups ?? []).enumerated() {
            try check("children in group \(i)", group.objectValue?["children"]?.arrayValue?.count, SceneLimits.maximumGroupChildren)
        }
    }

    // MARK: Layers

    private mutating func layer(_ value: SceneJSON, index i: Int, path: String) throws(SceneDecodeError) -> SceneLayer {
        let o = try object(value, path)
        guard let instanceValue = o["instance"] else { throw .malformed(path: path, reason: "\"instance\" is required") }
        guard let instance = instanceValue.numberValue?.uint64Value else {
            throw .malformed(path: ScenePath.key(path, "instance"), reason: "the instance ID must be a non-negative whole number")
        }
        let kind = try string(o, "kind", path)

        var values: [String: Double] = [:]
        if let v = o["values"] {
            let base = ScenePath.key(path, "values")
            for (name, number) in try object(v, base) { values[name] = try double(number, ScenePath.key(base, name)) }
        }

        let composite = try o["composite"].map { (c: SceneJSON) throws(SceneDecodeError) -> SceneComposite in
            try self.composite(c, ScenePath.key(path, "composite"))
        } ?? SceneComposite()

        var known: Set<String> = ["instance", "kind", "values", "composite"]
        let content: SceneLayerContent
        let contentPath = ScenePath.key(path, "content")
        switch kind {
        case "camera", "spectrum.circular", "spectrum.linear":
            if o["content"] != nil {
                warnings.append(SceneIssue(.droppedField, path: path, "\(path) has the unknown field \"content\"; it was dropped."))
            }
            known.insert("content")
            content = kind == "camera" ? .camera : kind == "spectrum.circular" ? .circularSpectrum : .linearSpectrum
        case "photo", "video", "text", "generator.graph":
            let key = try contentField(o["content"], "asset", contentPath)
            known.insert("content")
            switch kind {
            case "photo": content = .photo(asset: key)
            case "video": content = .video(asset: key)
            case "text": content = .text(asset: key)
            default: content = .generatorGraph(asset: key)
            }
        case "material":
            content = .material(id: try contentField(o["content"], "material", contentPath))
            known.insert("content")
        default:
            content = .unknown(kind: kind)
        }
        let extra = o.filter { (key: String, _: SceneJSON) -> Bool in !known.contains(key) }
        return SceneLayer(instance: instance, content: content, values: values, composite: composite, extra: extra)
    }

    /// `{"<field>": "<string>"}`; other keys are dropped with a warning.
    private mutating func contentField(_ value: SceneJSON?, _ field: String, _ path: String) throws(SceneDecodeError) -> String {
        guard let value else { throw .malformed(path: path, reason: "the layer's content is required") }
        let o = try object(value, path)
        let result = try string(o, field, path)
        dropUnknown(o, known: [field], path: path)
        return result
    }

    private mutating func composite(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> SceneComposite {
        let o = try object(value, path)
        dropUnknown(o, known: ["opacity", "blend", "transform", "fit", "mask"], path: path)
        var opacity = 1.0
        if let v = o["opacity"] {
            let raw = try double(v, ScenePath.key(path, "opacity"))
            opacity = min(max(raw, 0), 1)
            if opacity != raw { clamped(ScenePath.key(path, "opacity"), raw, "0.0…1.0", opacity) }
        }
        let blend = try o["blend"].map { (b: SceneJSON) throws(SceneDecodeError) -> String in
            try string(b, ScenePath.key(path, "blend"))
        } ?? SceneComposite.normalBlendMode
        let transform = try o["transform"].map { (t: SceneJSON) throws(SceneDecodeError) -> LayerTransform in
            try self.transform(t, ScenePath.key(path, "transform"))
        } ?? .identity
        let fit = try o["fit"].map { (f: SceneJSON) throws(SceneDecodeError) -> SceneFit in
            try self.fit(f, ScenePath.key(path, "fit"))
        }
        let mask: SceneMask? = try o["mask"].flatMap { (m: SceneJSON) throws(SceneDecodeError) -> SceneMask? in
            try self.mask(m, ScenePath.key(path, "mask"))
        }
        return SceneComposite(opacity: opacity, blendMode: blend, transform: transform, fit: fit, mask: mask)
    }

    /// CMP-007's saved form (contracts/shape-masks.md in specs/104): `shape` required; an unknown shape's
    /// object is kept verbatim; a known shape's other keys are dropped, its numbers clamped (one warning
    /// each); a polygon with < 3 or > 32 points or zero area drops the whole mask (nil, `droppedField`).
    private mutating func mask(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> SceneMask? {
        let o = try object(value, path)
        let shape = try string(o, "shape", path)
        guard LayerMaskShape.kindNames.contains(shape) else { return .unknown(shape: shape, object: o) }
        var known: Set<String> = ["shape", "feather", "inverted", "transform"]
        if shape == "rectangle" { known.insert("cornerRadius") }
        if shape == "polygon" { known.insert("points") }
        dropUnknown(o, known: known, path: path)
        let rawFeather: Double = try o["feather"].map { (v: SceneJSON) throws(SceneDecodeError) -> Double in
            try double(v, ScenePath.key(path, "feather"))
        } ?? 0
        var inverted = false
        if let v = o["inverted"] {
            guard let b = v.boolValue else {
                throw .malformed(path: ScenePath.key(path, "inverted"), reason: "expected a boolean, found \(v.typeName)")
            }
            inverted = b
        }
        let placement: LayerMaskTransform = try maskTransform(o["transform"], ScenePath.key(path, "transform"))
        let liveShape: LayerMaskShape
        switch shape {
        case "ellipse":
            liveShape = .ellipse
        case "rectangle":
            let raw: Double = try o["cornerRadius"].map { (v: SceneJSON) throws(SceneDecodeError) -> Double in
                try double(v, ScenePath.key(path, "cornerRadius"))
            } ?? 0
            liveShape = .rectangle(cornerRadius: raw)
            let r = LayerMask.cornerRadiusRange
            let stored: Double = min(max(raw, r.lowerBound), r.upperBound)
            if raw != stored { clamped(path + ".cornerRadius", raw, "\(r.lowerBound)…\(r.upperBound)", stored) }
        default:
            guard let pointsValue = o["points"] else { throw .malformed(path: ScenePath.key(path, "points"), reason: "a polygon needs points") }
            let items = try array(pointsValue, ScenePath.key(path, "points"))
            // Counted before any point is decoded (hostile input; CMP-007-R8).
            guard items.count >= 3, items.count <= LayerMask.maximumPolygonPoints else {
                warnings.append(SceneIssue(.droppedField, path: path,
                                           "\(path) has a polygon of \(items.count) points (3…\(LayerMask.maximumPolygonPoints) are drawn); the mask was dropped."))
                return nil
            }
            var points: [LayerPoint] = []
            let r = LayerMask.pointRange
            for (i, item) in items.enumerated() {
                let itemPath = ScenePath.index(ScenePath.key(path, "points"), i)
                let raw = try point(item, default: .zero, itemPath)
                let x: Double = min(max(raw.x, r.lowerBound), r.upperBound)
                let y: Double = min(max(raw.y, r.lowerBound), r.upperBound)
                if raw.x != x { clamped(itemPath + ".x", raw.x, "\(r.lowerBound)…\(r.upperBound)", x) }
                if raw.y != y { clamped(itemPath + ".y", raw.y, "\(r.lowerBound)…\(r.upperBound)", y) }
                points.append(raw)
            }
            liveShape = .polygon(points)
        }
        let f = LayerMask.featherRange
        let feather: Double = min(max(rawFeather, f.lowerBound), f.upperBound)
        if rawFeather != feather { clamped(path + ".feather", rawFeather, "\(f.lowerBound)…\(f.upperBound)", feather) }
        do {
            return .known(try LayerMask(shape: liveShape, transform: placement, feather: rawFeather, inverted: inverted))
        } catch {
            warnings.append(SceneIssue(.droppedField, path: path, "\(path) has an unusable polygon (\(error)); the mask was dropped."))
            return nil
        }
    }

    /// CMP-007's mask transform: `center`, `scale`, `rotation`, each optional; clamped with warnings.
    private mutating func maskTransform(_ value: SceneJSON?, _ path: String) throws(SceneDecodeError) -> LayerMaskTransform {
        guard let value else { return .identity }
        let o = try object(value, path)
        dropUnknown(o, known: ["center", "scale", "rotation"], path: path)
        let center = try point(o["center"], default: LayerPoint(x: 0.5, y: 0.5), ScenePath.key(path, "center"))
        let scale = try point(o["scale"], default: LayerPoint(x: 1, y: 1), ScenePath.key(path, "scale"))
        let rotation: Double = try o["rotation"].map { (r: SceneJSON) throws(SceneDecodeError) -> Double in
            try double(r, ScenePath.key(path, "rotation"))
        } ?? 0
        let t = LayerMaskTransform(center: center, scale: scale, rotation: rotation)
        func range(_ r: ClosedRange<Double>) -> String { "\(r.lowerBound)…\(r.upperBound)" }
        let checks: [(String, Double, Double, ClosedRange<Double>)] = [
            ("center.x", center.x, t.center.x, LayerMaskTransform.centerRange),
            ("center.y", center.y, t.center.y, LayerMaskTransform.centerRange),
            ("scale.x", scale.x, t.scale.x, LayerMaskTransform.scaleRange),
            ("scale.y", scale.y, t.scale.y, LayerMaskTransform.scaleRange),
        ]
        for (name, raw, stored, r) in checks where raw != stored {
            clamped(path + "." + name, raw, range(r), stored)
        }
        return t
    }

    /// CMP-006's saved form: `mode` required (any string kept), `anchor` optional (centre), its
    /// components clamped to 0…1 (one warning per component); other keys dropped.
    private mutating func fit(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> SceneFit {
        let o = try object(value, path)
        dropUnknown(o, known: ["mode", "anchor"], path: path)
        guard let modeValue = o["mode"] else { throw .malformed(path: ScenePath.key(path, "mode"), reason: "the fit mode is required") }
        let mode = try string(modeValue, ScenePath.key(path, "mode"))
        let raw = try point(o["anchor"], default: LayerPoint(x: 0.5, y: 0.5), ScenePath.key(path, "anchor"))
        let stored = LayerFit(mode: .fill, anchor: raw).anchor   // the live clamp (finite values: 0…1)
        if raw.x != stored.x { clamped(path + ".anchor.x", raw.x, "0.0…1.0", stored.x) }
        if raw.y != stored.y { clamped(path + ".anchor.y", raw.y, "0.0…1.0", stored.y) }
        return SceneFit(mode: mode, anchor: stored)
    }

    /// CMP-005's saved form: version 1 required, missing fields read identity values, out of range
    /// components clamped (one warning per component).
    private mutating func transform(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> LayerTransform {
        let o = try object(value, path)
        dropUnknown(o, known: ["version", "translation", "scale", "rotation", "anchor"], path: path)
        guard let versionNumber = o["version"]?.numberValue else {
            throw .malformed(path: ScenePath.key(path, "version"), reason: "the transform version is required")
        }
        guard versionNumber.int64Value == Int64(LayerTransform.formatVersion) else {
            throw .malformed(path: ScenePath.key(path, "version"), reason: "unsupported transform version \(versionNumber.text)")
        }
        let translation = try point(o["translation"], default: .zero, ScenePath.key(path, "translation"))
        let scale = try point(o["scale"], default: LayerPoint(x: 1, y: 1), ScenePath.key(path, "scale"))
        let rotation = try o["rotation"].map { (r: SceneJSON) throws(SceneDecodeError) -> Double in
            try double(r, ScenePath.key(path, "rotation"))
        } ?? 0
        let anchor = try point(o["anchor"], default: LayerPoint(x: 0.5, y: 0.5), ScenePath.key(path, "anchor"))
        let t: LayerTransform
        do {
            t = try LayerTransform(translation: translation, scale: scale, rotation: rotation, anchor: anchor)
        } catch {
            // Unreachable: decoded numbers are finite.
            throw .malformed(path: path, reason: "the transform is not finite")
        }
        func range(_ r: ClosedRange<Double>) -> String { "\(r.lowerBound)…\(r.upperBound)" }
        let checks: [(String, Double, Double, ClosedRange<Double>)] = [
            ("translation.x", translation.x, t.translation.x, LayerTransform.positionRange),
            ("translation.y", translation.y, t.translation.y, LayerTransform.positionRange),
            ("scale.x", scale.x, t.scale.x, LayerTransform.scaleRange),
            ("scale.y", scale.y, t.scale.y, LayerTransform.scaleRange),
            ("anchor.x", anchor.x, t.anchor.x, LayerTransform.positionRange),
            ("anchor.y", anchor.y, t.anchor.y, LayerTransform.positionRange),
        ]
        for (name, raw, stored, r) in checks where raw != stored {
            clamped(path + "." + name, raw, range(r), stored)
        }
        return t
    }

    private mutating func point(_ value: SceneJSON?, default fallback: LayerPoint, _ path: String) throws(SceneDecodeError) -> LayerPoint {
        guard let value else { return fallback }
        let o = try object(value, path)
        dropUnknown(o, known: ["x", "y"], path: path)
        let x = try o["x"].map { (v: SceneJSON) throws(SceneDecodeError) -> Double in try double(v, ScenePath.key(path, "x")) } ?? fallback.x
        let y = try o["y"].map { (v: SceneJSON) throws(SceneDecodeError) -> Double in try double(v, ScenePath.key(path, "y")) } ?? fallback.y
        return LayerPoint(x: x, y: y)
    }

    // MARK: Groups (CMP-011)

    /// `id` required (a whole number; its range is checked by validation); `name`, `enabled`, `opacity`
    /// (clamped with `valueClamped`), `transform` (CMP-005 form) and `children` optional; a child that is
    /// not a whole number is kept verbatim; unknown fields are kept.
    private mutating func group(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> SceneGroup {
        let o = try object(value, path)
        guard let idValue = o["id"] else { throw .malformed(path: path, reason: "\"id\" is required") }
        guard let id = idValue.numberValue?.uint64Value else {
            throw .malformed(path: ScenePath.key(path, "id"), reason: "the group ID must be a non-negative whole number")
        }
        let name = try o["name"].map { (n: SceneJSON) throws(SceneDecodeError) -> String in try string(n, ScenePath.key(path, "name")) } ?? ""
        var enabled = true
        if let e = o["enabled"] {
            guard let b = e.boolValue else {
                throw .malformed(path: ScenePath.key(path, "enabled"), reason: "expected a boolean, found \(e.typeName)")
            }
            enabled = b
        }
        var opacity = 1.0
        if let v = o["opacity"] {
            let raw = try double(v, ScenePath.key(path, "opacity"))
            opacity = min(max(raw, 0), 1)
            if opacity != raw { clamped(ScenePath.key(path, "opacity"), raw, "0.0…1.0", opacity) }
        }
        let transform = try o["transform"].map { (t: SceneJSON) throws(SceneDecodeError) -> LayerTransform in
            try self.transform(t, ScenePath.key(path, "transform"))
        } ?? .identity
        var children: [SceneGroupChild] = []
        if let list = o["children"] {
            for item in try array(list, ScenePath.key(path, "children")) {
                if let instance = item.numberValue?.uint64Value { children.append(.layer(instance)) } else { children.append(.other(item)) }
            }
        }
        let known: Set<String> = ["id", "name", "enabled", "opacity", "transform", "children"]
        return SceneGroup(id: id, name: name, enabled: enabled, opacity: opacity, transform: transform, children: children,
                          extra: o.filter { (key: String, _: SceneJSON) -> Bool in !known.contains(key) })
    }

    // MARK: Parameters

    private mutating func parameterValue(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> ParameterValue {
        let o = try object(value, path)
        dropUnknown(o, known: ["kind", "value"], path: path)
        let kind = try string(o, "kind", path)
        guard let v = o["value"] else { throw .malformed(path: path, reason: "\"value\" is required") }
        let valuePath = ScenePath.key(path, "value")
        switch kind {
        case "continuous":
            return .continuous(try double(v, valuePath))
        case "integer":
            guard let n = v.numberValue else { throw .malformed(path: valuePath, reason: "expected a number, found \(v.typeName)") }
            guard let i = n.int64Value, let int = Int(exactly: i) else {
                throw .malformed(path: valuePath, reason: "\(n.text) is not a whole number")
            }
            return .integer(int)
        case "boolean":
            guard let b = v.boolValue else { throw .malformed(path: valuePath, reason: "expected a boolean, found \(v.typeName)") }
            return .boolean(b)
        case "enum":
            return .enumeration(try string(v, valuePath))
        case "color":
            let items = try array(v, valuePath)
            guard items.count == 4 else { throw .malformed(path: valuePath, reason: "a color has exactly four components") }
            var c: [Double] = []
            for (i, item) in items.enumerated() { c.append(try double(item, ScenePath.index(valuePath, i))) }
            return .color(ParameterColor(red: c[0], green: c[1], blue: c[2], alpha: c[3]))
        default:
            throw .malformed(path: ScenePath.key(path, "kind"), reason: "unknown parameter value kind \"\(kind)\"")
        }
    }

    // MARK: Bindings and modulation

    private mutating func binding(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> SceneBinding {
        let o = try object(value, path)
        // An unknown audio feature is kept; validation flags the binding orphaned (MOD-013-R11).
        let sourceID = try string(o, "source", path)
        let target = ParameterID(try string(o, "target", path))
        var mapping = LinearMapping(outputStart: 0, outputEnd: 1)
        if let input = o["input"] {
            let p = ScenePath.key(path, "input")
            let io = try object(input, p)
            dropUnknown(io, known: ["minimum", "maximum"], path: p)
            if let v = io["minimum"] { mapping.inputMinimum = try double(v, ScenePath.key(p, "minimum")) }
            if let v = io["maximum"] { mapping.inputMaximum = try double(v, ScenePath.key(p, "maximum")) }
        }
        guard let output = o["output"] else { throw .malformed(path: path, reason: "\"output\" is required") }
        let op = ScenePath.key(path, "output")
        let oo = try object(output, op)
        dropUnknown(oo, known: ["start", "end"], path: op)
        guard let start = oo["start"], let end = oo["end"] else {
            throw .malformed(path: op, reason: "\"start\" and \"end\" are required")
        }
        mapping.outputStart = try double(start, ScenePath.key(op, "start"))
        mapping.outputEnd = try double(end, ScenePath.key(op, "end"))
        var mix = ModulationMixMode.replace
        if let m = o["mix"] {
            let text = try string(m, ScenePath.key(path, "mix"))
            guard let mode = ModulationMixMode(rawValue: text) else {
                throw .malformed(path: ScenePath.key(path, "mix"), reason: "unknown mix mode \"\(text)\"")
            }
            mix = mode
        }
        var envelope = AudioFeatureEnvelope.none
        if let e = o["envelope"] {
            let ep = ScenePath.key(path, "envelope")
            let eo = try object(e, ep)
            dropUnknown(eo, known: ["attack", "release"], path: ep)
            if let v = eo["attack"] { envelope.attackSeconds = try double(v, ScenePath.key(ep, "attack")) }
            if let v = eo["release"] { envelope.releaseSeconds = try double(v, ScenePath.key(ep, "release")) }
        }
        let expression = try o["expression"].map { (e: SceneJSON) throws(SceneDecodeError) -> String in
            try string(e, ScenePath.key(path, "expression"))
        }
        let known: Set<String> = ["source", "target", "input", "output", "mix", "envelope", "expression"]
        return SceneBinding(sourceID: sourceID, target: target, mapping: mapping, mix: mix, envelope: envelope, expression: expression,
                            extra: o.filter { (key: String, _: SceneJSON) -> Bool in !known.contains(key) })
    }

    private mutating func modulation(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> SceneModulation {
        let o = try object(value, path)
        dropUnknown(o, known: ["generators", "connections"], path: path)
        var result = SceneModulation()
        if let g = o["generators"] {
            let base = ScenePath.key(path, "generators")
            for (i, item) in try array(g, base).enumerated() {
                let p = ScenePath.index(base, i)
                let go = try object(item, p)
                dropUnknown(go, known: ["id", "name", "inputs"], path: p)
                var inputs: [String] = []
                if let list = go["inputs"] {
                    for (j, input) in try array(list, ScenePath.key(p, "inputs")).enumerated() {
                        inputs.append(try string(input, ScenePath.index(ScenePath.key(p, "inputs"), j)))
                    }
                }
                result.generators.append(ModulationGenerator(id: try string(go, "id", p), displayName: try string(go, "name", p),
                                                             inputs: inputs))
            }
        }
        if let c = o["connections"] {
            let base = ScenePath.key(path, "connections")
            for (i, item) in try array(c, base).enumerated() {
                let p = ScenePath.index(base, i)
                let co = try object(item, p)
                dropUnknown(co, known: ["source", "target", "input"], path: p)
                guard let s = co["source"], let t = co["target"] else {
                    throw .malformed(path: p, reason: "\"source\" and \"target\" are required")
                }
                let input = try co["input"].map { (v: SceneJSON) throws(SceneDecodeError) -> String in
                    try string(v, ScenePath.key(p, "input"))
                } ?? ModulationEdge.valueInput
                result.connections.append(SceneConnection(source: try node(s, ScenePath.key(p, "source")),
                                                          target: try node(t, ScenePath.key(p, "target")), input: input))
            }
        }
        return result
    }

    private mutating func node(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> SceneNodeRef {
        let o = try object(value, path)
        dropUnknown(o, known: ["kind", "id"], path: path)
        let kind = try string(o, "kind", path)
        let id = try string(o, "id", path)
        switch kind {
        case "audio": return .audio(id)   // unknown features are kept (MOD-013-R11)
        case "parameter": return .parameter(ParameterID(id))
        case "generator": return .generator(id)
        default: throw .malformed(path: ScenePath.key(path, "kind"), reason: "unknown node kind \"\(kind)\"")
        }
    }

    // MARK: Assets

    private func asset(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> SceneAsset {
        let o = try object(value, path)
        let type = try string(o, "type", path)
        var known: Set<String> = ["type"]
        let kind: SceneAssetKind
        switch type {
        case "photo", "video":
            let id = try string(o, "storeID", path)
            known.insert("storeID")
            kind = type == "photo" ? .photo(storeID: id) : .video(storeID: id)
        case "logo":   // MED-010
            let id = try string(o, "storeID", path)
            known.insert("storeID")
            kind = .logo(storeID: id)
        case "text":
            guard let spec = o["spec"] else { throw .malformed(path: path, reason: "\"spec\" is required") }
            known.insert("spec")
            kind = .text(spec: spec)
        case "generatorGraph":
            guard let document = o["document"] else { throw .malformed(path: path, reason: "\"document\" is required") }
            known.insert("document")
            kind = .generatorGraph(document: document)
        default:
            kind = .unknown(type: type)
        }
        return SceneAsset(kind, extra: o.filter { (key: String, _: SceneJSON) -> Bool in !known.contains(key) })
    }

    // MARK: Helpers

    private mutating func dropUnknown(_ o: [String: SceneJSON], known: Set<String>, path: String) {
        for key in o.keys.sorted(by: SceneJSONWriter.utf8Precedes) where !known.contains(key) {
            warnings.append(SceneIssue(.droppedField, path: path, "\(path) has the unknown field \"\(key)\"; it was dropped."))
        }
    }

    private mutating func clamped(_ path: String, _ raw: Double, _ range: String, _ stored: Double) {
        warnings.append(SceneIssue(.valueClamped, path: path, "\(path): \(raw) is outside \(range); read as \(stored)."))
    }

    private func object(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> [String: SceneJSON] {
        guard let o = value.objectValue else { throw .malformed(path: path, reason: "expected an object, found \(value.typeName)") }
        return o
    }

    private func array(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> [SceneJSON] {
        guard let a = value.arrayValue else { throw .malformed(path: path, reason: "expected an array, found \(value.typeName)") }
        return a
    }

    private func string(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> String {
        guard let s = value.stringValue else { throw .malformed(path: path, reason: "expected a string, found \(value.typeName)") }
        return s
    }

    private func string(_ o: [String: SceneJSON], _ key: String, _ path: String) throws(SceneDecodeError) -> String {
        guard let v = o[key] else { throw .malformed(path: path, reason: "\"\(key)\" is required") }
        return try string(v, ScenePath.key(path, key))
    }

    private func double(_ value: SceneJSON, _ path: String) throws(SceneDecodeError) -> Double {
        guard let n = value.numberValue else { throw .malformed(path: path, reason: "expected a number, found \(value.typeName)") }
        guard let d = n.doubleValue else { throw .malformed(path: path, reason: "\(n.text) is too large") }
        return d
    }
}
