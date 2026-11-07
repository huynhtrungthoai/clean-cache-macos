import Foundation
import Security
import CoreServices

// ── V2-APPS: facts about an installed app, each with its source (docs/plan-v2.md §6.3 / §7) ──
//
// Nothing here is inferred: version from Info.plist, publisher from the code signature's leaf
// certificate, install source from the App Store receipt / signing authority, last use from
// Spotlight. Missing data stays nil. No "unused" or "suspicious" label is derived from these
// (an unsigned app is `unsigned`, not suspicious; a missing last-used date is unknown, not unused).

public enum AppInstallSource: String, Sendable, Equatable {
    /// Has an App Store receipt, or is signed by Apple's Mac App Store authority.
    case appStore
    /// Signed by Apple itself (system / Apple apps outside the store).
    case apple
    /// Signed with a Developer ID certificate.
    case identifiedDeveloper
    /// Ad-hoc signature (no certificate).
    case adHoc
    case unsigned
    /// The signature could not be read.
    case unknown

    public var titleKey: String {
        switch self {
        case .appStore: return "App Store"
        case .apple: return "Apple"
        case .identifiedDeveloper: return "Identified developer"
        case .adHoc: return "Ad-hoc signed"
        case .unsigned: return "Not signed"
        case .unknown: return "Unknown source"
        }
    }
}

public struct AppMetadata: Equatable, Sendable {
    /// `CFBundleShortVersionString`; nil when absent.
    public var version: String?
    /// `CFBundleVersion`; nil when absent.
    public var build: String?
    /// Organisation from the signing certificate ("Google LLC"); nil when not signed by a named
    /// developer. Source: code signature.
    public var publisher: String?
    public var teamID: String?
    public var source: AppInstallSource
    /// The executable's signature checked out (main executable + certificate chain; resources
    /// not hashed, for speed). false when unsigned or invalid; nil = not checked.
    public var signatureValid: Bool?
    /// Spotlight's `kMDItemLastUsedDate`; nil = Spotlight has no record (not "never used").
    public var lastUsed: Date?

    public init(version: String? = nil, build: String? = nil, publisher: String? = nil, teamID: String? = nil,
                source: AppInstallSource = .unknown, signatureValid: Bool? = nil, lastUsed: Date? = nil) {
        self.version = version; self.build = build; self.publisher = publisher; self.teamID = teamID
        self.source = source; self.signatureValid = signatureValid; self.lastUsed = lastUsed
    }
}

/// "Developer ID Application: Google LLC (EQHXZ8M8AV)" → "Google LLC". Pure.
public func signingPublisher(fromLeafSummary s: String) -> String? {
    guard let colon = s.range(of: ": ") else { return nil }
    var name = String(s[colon.upperBound...])
    if let paren = name.range(of: " (", options: .backwards), name.hasSuffix(")") {
        name = String(name[..<paren.lowerBound])
    }
    name = name.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
}

/// Which signing authority a signature satisfied (checked with code requirements, not names).
public enum SigningAnchor: Sendable, Equatable {
    case apple                 // `anchor apple`: Apple's own software
    case macAppStore           // Mac App Store distribution certificate
    case developerID           // Developer ID Application
    case otherCertificate      // signed with some other certificate (e.g. development)
    case adHoc                 // signed without a certificate
    case unsigned
}

/// Install source from the receipt and the verified signing anchor. Pure.
public func appInstallSource(anchor: SigningAnchor?, hasReceipt: Bool) -> AppInstallSource {
    if hasReceipt { return .appStore }
    switch anchor {
    case .apple?: return .apple
    case .macAppStore?: return .appStore
    case .developerID?: return .identifiedDeveloper
    case .adHoc?: return .adHoc
    case .unsigned?: return .unsigned
    case .otherCertificate?, nil: return .unknown
    }
}

private func satisfies(_ code: SecStaticCode, _ text: String) -> Bool {
    var req: SecRequirement?
    guard SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess, let req else { return false }
    return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), req) == errSecSuccess
}

/// Reads the facts for one `.app`. Cost: Info.plist + signature of the main executable
/// (no resource hashing) + one Spotlight lookup. Call off the main thread.
public func appMetadata(at url: URL) -> AppMetadata {
    var m = AppMetadata()
    let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
    m.version = info?["CFBundleShortVersionString"] as? String
    m.build = info?["CFBundleVersion"] as? String
    let hasReceipt = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)

    var code: SecStaticCode?
    var anchor: SigningAnchor? = nil
    if SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code {
        var dict: CFDictionary?
        var leaf: String? = nil
        var signed = false, hasCerts = false
        if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &dict) == errSecSuccess,
           let d = dict as? [String: Any] {
            signed = d[kSecCodeInfoIdentifier as String] != nil
            m.teamID = d[kSecCodeInfoTeamIdentifier as String] as? String
            if let certs = d[kSecCodeInfoCertificates as String] as? [SecCertificate], let first = certs.first {
                hasCerts = true
                leaf = SecCertificateCopySubjectSummary(first) as String?
            }
        }
        if !signed {
            anchor = .unsigned
            m.signatureValid = false
        } else {
            let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
            m.signatureValid = SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
            if !hasCerts {
                anchor = .adHoc
            } else if m.signatureValid == true {
                if satisfies(code, "anchor apple") {
                    anchor = .apple
                } else if satisfies(code, "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9]") {
                    anchor = .macAppStore
                } else if satisfies(code, "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]") {
                    anchor = .developerID
                } else {
                    anchor = .otherCertificate
                }
            }
        }
        if anchor == .developerID, let leaf { m.publisher = signingPublisher(fromLeafSummary: leaf) }
    }
    m.source = appInstallSource(anchor: anchor, hasReceipt: hasReceipt)
    if m.source == .apple { m.publisher = "Apple" }

    if let item = MDItemCreateWithURL(nil, url as CFURL),
       let d = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
        m.lastUsed = d
    }
    return m
}
