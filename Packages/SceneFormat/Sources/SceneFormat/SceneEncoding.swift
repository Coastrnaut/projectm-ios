// SceneEncoding.swift — model → canonical JSON (SCN-001-R7; contract C1, C2).
//
// Known fields are always written (absent optional sections: `modulation` when empty, a binding's
// `expression` when nil, a camera's or spectrum's `content`). Preserved unknown fields are merged
// in; a known field of the same name wins.
import Compositor
import ParameterGraph

enum SceneEncoder {
    static func document(_ d: SceneDocument) -> SceneJSON {
        var o = d.extra
        o["format"] = .string(SceneDocument.formatName)
        o["version"] = .integer(Int64(SceneDocument.currentVersion))
        o["id"] = .string(d.id)
        o["name"] = .string(d.name)
        o["layers"] = .array(d.layers.map(layer))
        var parameters: [String: SceneJSON] = [:]
        for (id, value) in d.parameters { parameters[id.rawValue] = parameterValue(value) }
        o["parameters"] = .object(parameters)
        o["bindings"] = .array(d.bindings.map(binding))
        var assets: [String: SceneJSON] = [:]
        for (key, a) in d.assets { assets[key] = asset(a) }
        o["assets"] = .object(assets)
        if d.modulation.isEmpty {
            o["modulation"] = nil
        } else {
            o["modulation"] = modulation(d.modulation)
        }
        if !d.groups.isEmpty { o["groups"] = .array(d.groups.map(group)) }   // CMP-011: only when set (older scenes byte-identical)
        if let effects = d.effects { o["effects"] = .array(effects.map(\.json)) }   // FX-020: likewise
        return .object(o)
    }

    static func layer(_ l: SceneLayer) -> SceneJSON {
        var o = l.extra
        o["instance"] = .number(SceneNumber(l.instance))
        o["kind"] = .string(l.content.kind)
        var values: [String: SceneJSON] = [:]
        for (name, v) in l.values { values[name] = .double(v) }
        o["values"] = .object(values)
        o["composite"] = composite(l.composite)
        switch l.content {
        case .camera, .circularSpectrum, .linearSpectrum:
            o["content"] = nil
        case let .photo(key), let .video(key), let .text(key), let .generatorGraph(key):
            o["content"] = .object(["asset": .string(key)])
        case let .material(id):
            o["content"] = .object(["material": .string(id)])
        case .unknown:
            break // its content, if any, is in `extra`
        }
        return .object(o)
    }

    static func composite(_ c: SceneComposite) -> SceneJSON {
        var o: [String: SceneJSON] = ["opacity": .double(c.opacity), "blend": .string(c.blendMode), "transform": transform(c.transform)]
        if let f = c.fit { o["fit"] = fit(f) }   // CMP-006: only when set, so older scenes stay byte-identical
        if let m = c.mask { o["mask"] = mask(m) }   // CMP-007: likewise
        return .object(o)
    }

    /// CMP-007's saved form: every field of a known shape; an unknown shape's object verbatim.
    static func mask(_ m: SceneMask) -> SceneJSON {
        switch m {
        case let .unknown(_, object):
            return .object(object)
        case let .known(mask):
            let t: LayerMaskTransform = mask.transform
            let placement: SceneJSON = .object(["center": point(t.center), "scale": point(t.scale), "rotation": .double(t.rotation)])
            var o: [String: SceneJSON] = ["shape": .string(mask.shape.kindName), "feather": .double(mask.feather),
                                          "inverted": .bool(mask.inverted), "transform": placement]
            switch mask.shape {
            case .ellipse: break
            case let .rectangle(radius): o["cornerRadius"] = .double(radius)
            case let .polygon(points): o["points"] = .array(points.map(point))
            }
            return .object(o)
        }
    }

    /// CMP-006's saved form.
    static func fit(_ f: SceneFit) -> SceneJSON {
        .object(["mode": .string(f.mode), "anchor": point(f.anchor)])
    }

    /// CMP-005's saved form, version 1.
    static func transform(_ t: LayerTransform) -> SceneJSON {
        .object(["version": .integer(Int64(LayerTransform.formatVersion)), "translation": point(t.translation),
                 "scale": point(t.scale), "rotation": .double(t.rotation), "anchor": point(t.anchor)])
    }

    static func point(_ p: LayerPoint) -> SceneJSON { .object(["x": .double(p.x), "y": .double(p.y)]) }

    /// MOD-001's tagged form.
    static func parameterValue(_ v: ParameterValue) -> SceneJSON {
        let value: SceneJSON = switch v {
        case let .continuous(d): .double(d)
        case let .integer(i): .integer(Int64(i))
        case let .boolean(b): .bool(b)
        case let .enumeration(s): .string(s)
        case let .color(c): .array(c.components.map { (x: Double) -> SceneJSON in .double(x) })
        }
        return .object(["kind": .string(v.kindName), "value": value])
    }

    static func binding(_ b: SceneBinding) -> SceneJSON {
        var o = b.extra
        o["source"] = .string(b.sourceID)
        o["target"] = .string(b.target.rawValue)
        o["input"] = .object(["minimum": .double(b.mapping.inputMinimum), "maximum": .double(b.mapping.inputMaximum)])
        o["output"] = .object(["start": .double(b.mapping.outputStart), "end": .double(b.mapping.outputEnd)])
        o["mix"] = .string(b.mix.rawValue)
        o["envelope"] = .object(["attack": .double(b.envelope.attackSeconds), "release": .double(b.envelope.releaseSeconds)])
        o["expression"] = b.expression.map { (s: String) -> SceneJSON in .string(s) }
        // MOD-004: only a non-linear curve is written, so linear bindings are stored as before; an
        // unreadable stored curve in `extra` passes through unchanged.
        if b.curve != .linear { o["curve"] = curve(b.curve) }
        return .object(o)
    }

    /// MOD-004's stored form (contract K8).
    static func curve(_ c: MappingCurve) -> SceneJSON {
        var o: [String: SceneJSON] = ["kind": .string(c.kindName)]
        switch c {
        case .linear:
            break
        case let .easeIn(p), let .easeOut(p), let .easeInOut(p):
            o["exponent"] = .double(p)
        case let .logarithmic(k), let .exponential(k):
            o["strength"] = .double(k)
        case let .piecewise(points):
            o["points"] = .array(points.map { (p: CurvePoint) -> SceneJSON in .object(["x": .double(p.x), "y": .double(p.y)]) })
        }
        return .object(o)
    }

    static func modulation(_ m: SceneModulation) -> SceneJSON {
        .object([
            "generators": .array(m.generators.map { (g: ModulationGenerator) -> SceneJSON in
                .object(["id": .string(g.id), "name": .string(g.displayName),
                         "inputs": .array(g.inputs.map { (i: String) -> SceneJSON in .string(i) })])
            }),
            "connections": .array(m.connections.map { (e: SceneConnection) -> SceneJSON in
                .object(["source": node(e.source), "target": node(e.target), "input": .string(e.input)])
            }),
        ])
    }

    static func node(_ n: SceneNodeRef) -> SceneJSON {
        .object(["kind": .string(n.kindName), "id": .string(n.id)])
    }

    static func asset(_ a: SceneAsset) -> SceneJSON {
        var o = a.extra
        o["type"] = .string(a.kind.typeName)
        switch a.kind {
        case let .photo(id), let .video(id), let .logo(id): o["storeID"] = .string(id)
        case let .text(spec): o["spec"] = spec
        case let .generatorGraph(document): o["document"] = document
        case .unknown: break
        }
        return .object(o)
    }
}

extension SceneDocument {
    /// The document as a JSON value (its canonical content).
    public var json: SceneJSON { SceneEncoder.document(self) }

    /// Canonical UTF-8 bytes (contract C2).
    public func encoded() -> [UInt8] { SceneJSONWriter.write(json) }
}

extension SceneJSON {
    /// Canonical UTF-8 bytes of this value (contract C2).
    public var canonicalBytes: [UInt8] { SceneJSONWriter.write(self) }
}
