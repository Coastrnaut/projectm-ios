// ParameterDescriptor.swift — everything a consumer needs to know about one parameter
// (MOD-001-R2; data-model.md).

/// Where a descriptor was written, so a duplicate-ID error can name both registrations.
public struct ParameterRegistrationSite: Sendable, Hashable, CustomStringConvertible {
    public let fileID: String
    public let line: Int

    public init(fileID: String, line: Int) {
        self.fileID = fileID
        self.line = line
    }

    public var description: String { "\(fileID):\(line)" }
}

public struct ParameterDescriptor: Sendable, Hashable {
    public let id: ParameterID
    public let displayName: String
    public let group: ParameterGroup
    public let unit: ParameterUnit
    public let kind: ParameterKind
    public let modulation: ModulationPolicy
    public let registrationSite: ParameterRegistrationSite

    public init(id: ParameterID, displayName: String, group: ParameterGroup, unit: ParameterUnit,
                kind: ParameterKind, modulation: ModulationPolicy,
                fileID: String = #fileID, line: Int = #line) {
        self.id = id
        self.displayName = displayName
        self.group = group
        self.unit = unit
        self.kind = kind
        self.modulation = modulation
        self.registrationSite = ParameterRegistrationSite(fileID: fileID, line: line)
    }

    public var defaultValue: ParameterValue { kind.defaultValue }
}
