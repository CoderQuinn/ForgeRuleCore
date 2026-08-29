//
//  ForgeRuleCoreBundle.swift
//  ForgeRuleCore
//
//  Created by MagicianQuinn on 2026/2/11.
//

import Foundation

public enum ForgeRuleCoreBundleResource: String, Sendable, Equatable {
    case geosite = "geosite.json"
    case geoIP = "geoip.mmdb"
}

public enum ForgeRuleCoreBundleResourceFailure: Sendable, Equatable {
    case unreadableOrMalformed
    case mmdbOpenFailed(status: Int32)
}

public enum ForgeRuleCoreBundleError: Error, Sendable, Equatable {
    /// No shared container URL for this App Group (invalid id, entitlements, or simulator setup).
    case invalidAppGroupIdentifier(String)
    case missingResource(resource: ForgeRuleCoreBundleResource, path: String)
    case invalidResource(
        resource: ForgeRuleCoreBundleResource,
        path: String,
        failure: ForgeRuleCoreBundleResourceFailure
    )
}

extension ForgeRuleCoreBundleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidAppGroupIdentifier(let id):
            return "No App Group container URL for identifier: \(id)"
        case .missingResource(let resource, let path):
            return "Missing \(resource.rawValue) at path: \(path)"
        case .invalidResource(let resource, let path, let failure):
            switch failure {
            case .unreadableOrMalformed:
                return "Unreadable or malformed \(resource.rawValue) at path: \(path)"
            case .mmdbOpenFailed(let status):
                return "Invalid \(resource.rawValue) at path: \(path) (MMDB status=\(status))"
            }
        }
    }
}

public enum ForgeRuleCoreBundle {
    /// Relative directory shared with the QuantumLink App Group path contract.
    public static let rulesSubdirectory = "Rules"

    public static func makeRuleCore(
        appGroup: String,
        rules: [Rule]
    ) throws -> RuleCore {
        try makeRuleCore(
            appGroup: appGroup,
            rules: rules,
            containerURLResolver: { identifier in
                FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: identifier
                )
            }
        )
    }

    static func makeRuleCore(
        appGroup: String,
        rules: [Rule],
        containerURLResolver: (String) -> URL?
    ) throws -> RuleCore {
        let normalizedAppGroup = appGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAppGroup.isEmpty,
            let base = containerURLResolver(normalizedAppGroup)
        else {
            throw ForgeRuleCoreBundleError.invalidAppGroupIdentifier(appGroup)
        }

        let rulesDirectory = base.appendingPathComponent(rulesSubdirectory, isDirectory: true)
        return try makeRuleCore(resourceDirectory: rulesDirectory, rules: rules)
    }

    static func makeRuleCore(
        resourceDirectory: URL,
        rules: [Rule],
        fileManager: FileManager = .default
    ) throws -> RuleCore {
        let geositeURL = resourceDirectory.appendingPathComponent(
            ForgeRuleCoreBundleResource.geosite.rawValue
        )
        let geoipURL = resourceDirectory.appendingPathComponent(
            ForgeRuleCoreBundleResource.geoIP.rawValue
        )

        try requireFile(.geosite, at: geositeURL, fileManager: fileManager)
        try requireFile(.geoIP, at: geoipURL, fileManager: fileManager)

        let geosite: GeoSiteDB
        do {
            geosite = try GeoSiteDB(jsonURL: geositeURL)
        } catch {
            throw ForgeRuleCoreBundleError.invalidResource(
                resource: .geosite,
                path: geositeURL.path,
                failure: .unreadableOrMalformed
            )
        }

        let lookup: MMDBCountryLookup
        do {
            lookup = try MMDBCountryLookup(url: geoipURL)
        } catch let error as MMDBOpenError {
            throw ForgeRuleCoreBundleError.invalidResource(
                resource: .geoIP,
                path: geoipURL.path,
                failure: .mmdbOpenFailed(status: error.status)
            )
        } catch {
            throw ForgeRuleCoreBundleError.invalidResource(
                resource: .geoIP,
                path: geoipURL.path,
                failure: .unreadableOrMalformed
            )
        }

        let geoipKeys: [String] = rules.flatMap { $0.condition.collectGeoipKeys() }
        let geoip = GeoIPDB(lookup: lookup, preheatKeys: geoipKeys)

        let engine = RuleEngine(rules: rules, geosite: geosite, geoip: geoip)

        return RuleCore(engine: engine)
    }

    private static func requireFile(
        _ resource: ForgeRuleCoreBundleResource,
        at url: URL,
        fileManager: FileManager
    ) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            throw ForgeRuleCoreBundleError.missingResource(
                resource: resource,
                path: url.path
            )
        }
    }

    public static func makeFlowClassifier(
        appGroup: String,
        rules: [Rule],
        fakeIPStore: FakeIPStore? = nil
    ) throws -> FlowRuleClassifier {
        let core = try makeRuleCore(appGroup: appGroup, rules: rules)
        let resolver = FlowFactsResolver(fakeIPStore: fakeIPStore)
        return FlowRuleClassifier(resolver: resolver, core: core)
    }
}
