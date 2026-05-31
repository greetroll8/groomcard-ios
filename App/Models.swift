import Foundation

// MARK: - Enums

enum PetSpecies: String, CaseIterable, Codable, Identifiable {
    case dog = "Dog"
    case cat = "Cat"
    case other = "Other"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .dog: return "dog"
        case .cat: return "cat"
        case .other: return "pawprint"
        }
    }
}

enum CoatType: String, CaseIterable, Codable, Identifiable {
    case short = "Short"
    case double = "Double"
    case curly = "Curly"
    case wire = "Wire"
    case silky = "Silky"
    case wool = "Wool"
    case hairless = "Hairless"
    case unknown = "Unknown"

    var id: String { rawValue }
}

enum BehaviorFlag: String, CaseIterable, Codable, Identifiable {
    case bite = "Bite risk"
    case anxious = "Anxious"
    case senior = "Senior"
    case none = "None"

    var id: String { rawValue }

    /// Flags that should be visually emphasized as danger (text + color, never color alone).
    var isDanger: Bool {
        self == .bite
    }

    var symbolName: String {
        switch self {
        case .bite: return "exclamationmark.triangle"
        case .anxious: return "waveform.path.ecg"
        case .senior: return "hourglass"
        case .none: return "checkmark.circle"
        }
    }
}

enum WeightUnit: String, CaseIterable, Codable, Identifiable {
    case kg = "kg"
    case lb = "lb"

    var id: String { rawValue }

    static var deviceDefault: WeightUnit {
        Locale.current.measurementSystem == .metric ? .kg : .lb
    }
}

enum ConsentFrequency: String, CaseIterable, Codable, Identifiable {
    case everyVisit = "Every visit"
    case yearly = "Once a year"

    var id: String { rawValue }
}

/// What kind of entity a PhotoAsset is attached to.
enum PhotoRefType: String, Codable {
    case pet
    case sessionBefore
    case sessionAfter
    case consentSignature
    case styleReference
}

enum DocumentLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case russian = "ru"
    case german = "de"
    case spanish = "es"
    case french = "fr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .french: return "Français"
        }
    }

    static var deviceDefault: DocumentLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return DocumentLanguage(rawValue: code) ?? .english
    }
}

// MARK: - Owner

struct Owner: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var phone: String = ""
    var email: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    static let sample = Owner(name: "Sample Owner", phone: "+1 555 0100", email: "owner@example.com")
}

// MARK: - Pet

struct Pet: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var species: PetSpecies = .dog
    var breed: String = ""
    var coatType: CoatType = .unknown
    var behaviorFlags: [BehaviorFlag] = []
    var allergies: String = ""
    var weight: Double?
    var weightUnit: WeightUnit = WeightUnit.deviceDefault
    var rabiesExpiry: Date?
    var ownerId: UUID
    var mainPhotoId: UUID?
    var stylePreference: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// True when a rabies expiry exists and is in the past.
    var isRabiesExpired: Bool {
        guard let rabiesExpiry else { return false }
        return rabiesExpiry < Date()
    }

    var hasBiteRisk: Bool {
        behaviorFlags.contains(.bite)
    }

    /// Effective flags for display, hiding `.none` when real flags exist.
    var displayFlags: [BehaviorFlag] {
        let real = behaviorFlags.filter { $0 != .none }
        return real.isEmpty ? [] : real
    }

    static let sample = Pet(name: "Sample Pet", breed: "Poodle", coatType: .curly, ownerId: UUID())
}

// MARK: - GroomSession

struct GroomSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var petId: UUID
    var date: Date = Date()
    var style: String = ""
    var beforePhotoIds: [UUID] = []
    var afterPhotoIds: [UUID] = []
    var notes: String = ""
    var recommendations: String = ""
    var price: Decimal?
    var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var hasBefore: Bool { !beforePhotoIds.isEmpty }
    var hasAfter: Bool { !afterPhotoIds.isEmpty }

    static let sample = GroomSession(petId: UUID(), style: "Summer cut")
}

// MARK: - Consent

struct Consent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var petId: UUID
    var textVersion: String = "1"
    var resolvedText: String = ""
    var signaturePhotoId: UUID?
    var signedAt: Date = Date()
    var photoReleaseAllowed: Bool = false
    var matRemovalChoice: MatRemovalChoice = .brush
    var sedationFreeAcknowledged: Bool = true
    var seniorRiskAcknowledged: Bool = false
    var createdAt: Date = Date()

    enum MatRemovalChoice: String, CaseIterable, Codable, Identifiable {
        case brush = "Brush out mats"
        case shave = "Shave out mats"

        var id: String { rawValue }
    }

    var isSigned: Bool { signaturePhotoId != nil }

    static let sample = Consent(petId: UUID())
}

// MARK: - PhotoAsset

struct PhotoAsset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var thumbnailFileName: String?
    var refType: PhotoRefType
    var refId: UUID
    var createdAt: Date = Date()
}

// MARK: - Business info

struct BusinessInfo: Codable, Hashable {
    var name: String = ""
    var phone: String = ""
    var email: String = ""
    var address: String = ""
    var licenseNumber: String = ""
}

// MARK: - AppSettings

struct AppSettings: Codable, Equatable {
    var businessInfo: BusinessInfo = BusinessInfo()
    var consentTemplate: String = AppSettings.defaultConsentTemplate
    var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    var weightUnit: WeightUnit = WeightUnit.deviceDefault
    var consentFrequency: ConsentFrequency = .yearly
    var consentTextVersion: String = "1"
    var documentLanguage: DocumentLanguage = DocumentLanguage.deviceDefault
    var hasCompletedOnboarding: Bool = false
    var isPro: Bool = false

    static let defaultConsentTemplate = """
    I, the owner of the pet named below, authorize the groomer to perform grooming services.

    \u{2022} Matted coat: I understand that severely matted coats may require shaving rather than brushing, and that hidden skin issues may be found underneath.
    \u{2022} Senior/at-risk pets: I understand that grooming an older or health-compromised pet carries additional risk, and I accept it.
    \u{2022} No sedation: I understand the groomer does not use sedation. Pets that cannot be safely handled may have services stopped.
    \u{2022} Photo release: I indicate below whether the groomer may use before/after photos publicly.

    By signing, I confirm the above and that the information I provided is accurate.
    """
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case businessInfo, consentTemplate, currencyCode, weightUnit, consentFrequency
        case consentTextVersion, documentLanguage, hasCompletedOnboarding, isPro
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        businessInfo = try container.decodeIfPresent(BusinessInfo.self, forKey: .businessInfo) ?? defaults.businessInfo
        consentTemplate = try container.decodeIfPresent(String.self, forKey: .consentTemplate) ?? defaults.consentTemplate
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? defaults.currencyCode
        let weightRaw = try container.decodeIfPresent(String.self, forKey: .weightUnit)
        weightUnit = WeightUnit(rawValue: weightRaw ?? "") ?? defaults.weightUnit
        let freqRaw = try container.decodeIfPresent(String.self, forKey: .consentFrequency)
        consentFrequency = ConsentFrequency(rawValue: freqRaw ?? "") ?? defaults.consentFrequency
        consentTextVersion = try container.decodeIfPresent(String.self, forKey: .consentTextVersion) ?? defaults.consentTextVersion
        let langRaw = try container.decodeIfPresent(String.self, forKey: .documentLanguage)
        documentLanguage = DocumentLanguage(rawValue: langRaw ?? "") ?? defaults.documentLanguage
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? defaults.hasCompletedOnboarding
        isPro = try container.decodeIfPresent(Bool.self, forKey: .isPro) ?? defaults.isPro
    }
}

// MARK: - Filters / Sort

enum PetFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case biteRisk = "Bite risk"
    case rabiesExpired = "Rabies expired"
    case noConsent = "No consent"

    var id: String { rawValue }
}

enum PetSort: String, CaseIterable, Identifiable {
    case updated = "Recently updated"
    case name = "Name"
    case lastSession = "Last session"

    var id: String { rawValue }
}

// MARK: - CSV export period

enum ExportPeriod: String, CaseIterable, Identifiable {
    case all = "All time"
    case thisMonth = "This month"
    case last30 = "Last 30 days"
    case thisYear = "This year"

    var id: String { rawValue }

    /// Inclusive lower bound for the period; nil means no lower bound.
    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .all:
            return nil
        case .thisMonth:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        case .last30:
            return calendar.date(byAdding: .day, value: -30, to: now)
        case .thisYear:
            return calendar.date(from: calendar.dateComponents([.year], from: now))
        }
    }
}

// MARK: - Paywall trigger

enum PaywallTrigger: String, Identifiable {
    case petLimit = "Pet limit"
    case pdfExport = "PDF export"
    case consentPDF = "Consent PDF"
    case backup = "Backup"

    var id: String { rawValue }
}
