import Combine
import Foundation
import StoreKit

@MainActor
final class GroomStore: ObservableObject {
    static let proProductIDs = [
        "com.greetroll8.groomcard.monthly",
        "com.greetroll8.groomcard.yearly",
        "com.greetroll8.groomcard.lifetime"
    ]

    @Published private(set) var owners: [Owner] = []
    @Published private(set) var pets: [Pet] = []
    @Published private(set) var sessions: [GroomSession] = []
    @Published private(set) var consents: [Consent] = []
    @Published private(set) var photos: [PhotoAsset] = []
    @Published private(set) var saveError: String?
    @Published var settings = AppSettings() {
        didSet {
            if !isLoading { save() }
        }
    }

    private let fileURL: URL
    private var entitlementTask: Task<Void, Never>?
    private var isLoading = false
    private static let csvDateFormatter = ISO8601DateFormatter()
    private static let proProductIDSet = Set(proProductIDs)

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        if !fileManager.fileExists(atPath: support.path) {
            try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        }
        fileURL = support.appendingPathComponent("groomcard-store.json")
        load()
        startEntitlementRefresh()
    }

    // MARK: - Free limit / Pro

    var freeLimit: Int { 10 }

    var isOverFreeLimit: Bool {
        !settings.isPro && pets.count >= freeLimit
    }

    var isPro: Bool { settings.isPro }

    // MARK: - Derived collections

    func owner(id: UUID?) -> Owner? {
        guard let id else { return nil }
        return owners.first { $0.id == id }
    }

    func pet(id: UUID?) -> Pet? {
        guard let id else { return nil }
        return pets.first { $0.id == id }
    }

    /// Pets that belong to a given owner, most recently updated first.
    func pets(forOwner ownerId: UUID) -> [Pet] {
        pets.filter { $0.ownerId == ownerId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// All sessions for a pet, newest first.
    func sessions(forPet petId: UUID) -> [GroomSession] {
        sessions.filter { $0.petId == petId }
            .sorted { $0.date > $1.date }
    }

    func lastSession(forPet petId: UUID) -> GroomSession? {
        sessions(forPet: petId).first
    }

    /// All consents for a pet, newest first.
    func consents(forPet petId: UUID) -> [Consent] {
        consents.filter { $0.petId == petId }
            .sorted { $0.signedAt > $1.signedAt }
    }

    func latestConsent(forPet petId: UUID) -> Consent? {
        consents(forPet: petId).first
    }

    /// True when a fresh consent is required given the configured frequency.
    func needsConsent(forPet petId: UUID) -> Bool {
        guard let latest = latestConsent(forPet: petId), latest.isSigned else { return true }
        switch settings.consentFrequency {
        case .everyVisit:
            return true
        case .yearly:
            guard let oneYearLater = Calendar.current.date(byAdding: .year, value: 1, to: latest.signedAt) else {
                return true
            }
            return Date() > oneYearLater
        }
    }

    /// Sessions whose date falls on the current calendar day, newest first.
    var todaySessions: [GroomSession] {
        let calendar = Calendar.current
        return sessions
            .filter { calendar.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    var expiredRabiesPets: [Pet] {
        pets.filter(\.isRabiesExpired)
    }

    // MARK: - Search & filter

    func filteredPets(search: String, filter: PetFilter, sort: PetSort) -> [Pet] {
        var result = pets

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { pet in
                if pet.name.lowercased().contains(query) { return true }
                if pet.breed.lowercased().contains(query) { return true }
                if let owner = owner(id: pet.ownerId), owner.name.lowercased().contains(query) { return true }
                return false
            }
        }

        switch filter {
        case .all:
            break
        case .biteRisk:
            result = result.filter(\.hasBiteRisk)
        case .rabiesExpired:
            result = result.filter(\.isRabiesExpired)
        case .noConsent:
            result = result.filter { needsConsent(forPet: $0.id) }
        }

        switch sort {
        case .updated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastSession:
            result.sort { lhs, rhs in
                let l = lastSession(forPet: lhs.id)?.date ?? .distantPast
                let r = lastSession(forPet: rhs.id)?.date ?? .distantPast
                return l > r
            }
        }
        return result
    }

    func filteredOwners(search: String) -> [Owner] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = query.isEmpty
            ? owners
            : owners.filter {
                $0.name.lowercased().contains(query)
                    || $0.phone.lowercased().contains(query)
                    || $0.email.lowercased().contains(query)
            }
        return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Photos

    func photo(id: UUID?) -> PhotoAsset? {
        guard let id else { return nil }
        return photos.first { $0.id == id }
    }

    func photos(ids: [UUID]) -> [PhotoAsset] {
        ids.compactMap { id in photos.first { $0.id == id } }
    }

    /// Registers a stored image file as a PhotoAsset and returns its id.
    @discardableResult
    func addPhoto(fileName: String, thumbnailFileName: String? = nil, refType: PhotoRefType, refId: UUID) -> UUID {
        let asset = PhotoAsset(
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            refType: refType,
            refId: refId
        )
        photos.append(asset)
        save()
        return asset.id
    }

    func removePhoto(id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let asset = photos[index]
        ImageStore.delete(fileName: asset.fileName)
        ImageStore.delete(fileName: asset.thumbnailFileName)
        photos.remove(at: index)
        // Detach from any referencing entities.
        for i in pets.indices where pets[i].mainPhotoId == id {
            pets[i].mainPhotoId = nil
        }
        for i in sessions.indices {
            sessions[i].beforePhotoIds.removeAll { $0 == id }
            sessions[i].afterPhotoIds.removeAll { $0 == id }
        }
        for i in consents.indices where consents[i].signaturePhotoId == id {
            consents[i].signaturePhotoId = nil
        }
        save()
    }

    // MARK: - Owner CRUD

    func add(_ owner: Owner) {
        owners.insert(owner, at: 0)
        save()
    }

    func update(_ owner: Owner) {
        guard let index = owners.firstIndex(where: { $0.id == owner.id }) else { return }
        var updated = owner
        updated.updatedAt = Date()
        owners[index] = updated
        save()
    }

    func deleteOwner(id: UUID) {
        // Delete owner's pets first (cascade).
        for pet in pets where pet.ownerId == id {
            deletePet(id: pet.id)
        }
        owners.removeAll { $0.id == id }
        save()
    }

    // MARK: - Pet CRUD

    /// Adds a pet, enforcing the free limit. Returns false (and sets saveError) when blocked.
    @discardableResult
    func add(_ pet: Pet) -> Bool {
        guard !isOverFreeLimit else {
            saveError = "Free plan is limited to \(freeLimit) pets. Upgrade to add more."
            return false
        }
        pets.insert(pet, at: 0)
        save()
        return true
    }

    func update(_ pet: Pet) {
        guard let index = pets.firstIndex(where: { $0.id == pet.id }) else { return }
        var updated = pet
        updated.updatedAt = Date()
        pets[index] = updated
        save()
    }

    func deletePet(id: UUID) {
        // Remove dependent photos, sessions, consents.
        for asset in photos where (asset.refType == .pet || asset.refType == .styleReference) && asset.refId == id {
            ImageStore.delete(fileName: asset.fileName)
            ImageStore.delete(fileName: asset.thumbnailFileName)
        }
        for session in sessions(forPet: id) {
            deleteSession(id: session.id)
        }
        for consent in consents(forPet: id) {
            deleteConsent(id: consent.id)
        }
        photos.removeAll { ($0.refType == .pet || $0.refType == .styleReference) && $0.refId == id }
        pets.removeAll { $0.id == id }
        save()
    }

    // MARK: - GroomSession CRUD

    @discardableResult
    func add(_ session: GroomSession) -> GroomSession {
        var created = session
        if created.currencyCode.isEmpty { created.currencyCode = settings.currencyCode }
        sessions.insert(created, at: 0)
        save()
        return created
    }

    func update(_ session: GroomSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var updated = session
        updated.updatedAt = Date()
        sessions[index] = updated
        save()
    }

    func deleteSession(id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let photoIds = session.beforePhotoIds + session.afterPhotoIds
        for assetId in photoIds {
            if let asset = photo(id: assetId) {
                ImageStore.delete(fileName: asset.fileName)
                ImageStore.delete(fileName: asset.thumbnailFileName)
            }
        }
        photos.removeAll { photoIds.contains($0.id) }
        sessions.removeAll { $0.id == id }
        save()
    }

    /// Builds a new draft session for a pet, seeding style/recommendations from the last session (repeat defaults).
    func newDraftSession(forPet petId: UUID) -> GroomSession {
        var draft = GroomSession(petId: petId)
        draft.currencyCode = settings.currencyCode
        if let last = lastSession(forPet: petId) {
            draft.style = last.style
            draft.recommendations = last.recommendations
        } else if let pet = pet(id: petId), !pet.stylePreference.isEmpty {
            draft.style = pet.stylePreference
        }
        return draft
    }

    // MARK: - Consent CRUD

    @discardableResult
    func add(_ consent: Consent) -> Consent {
        var created = consent
        if created.resolvedText.isEmpty { created.resolvedText = settings.consentTemplate }
        if created.textVersion.isEmpty { created.textVersion = settings.consentTextVersion }
        consents.insert(created, at: 0)
        save()
        return created
    }

    func update(_ consent: Consent) {
        guard let index = consents.firstIndex(where: { $0.id == consent.id }) else { return }
        consents[index] = consent
        save()
    }

    func deleteConsent(id: UUID) {
        if let consent = consents.first(where: { $0.id == id }), let sigId = consent.signaturePhotoId,
           let asset = photo(id: sigId) {
            ImageStore.delete(fileName: asset.fileName)
            ImageStore.delete(fileName: asset.thumbnailFileName)
            photos.removeAll { $0.id == sigId }
        }
        consents.removeAll { $0.id == id }
        save()
    }

    /// Builds a fresh consent draft for a pet from the current template/version.
    func newDraftConsent(forPet petId: UUID) -> Consent {
        Consent(
            petId: petId,
            textVersion: settings.consentTextVersion,
            resolvedText: settings.consentTemplate,
            photoReleaseAllowed: false
        )
    }

    // MARK: - Sequential numbering

    /// Human-readable sequential report number, e.g. "GC-2026-0007".
    func nextReportNumber() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let count = sessions.count + 1
        return "GC-\(year)-\(String(format: "%04d", count))"
    }

    /// Human-readable sequential consent number, e.g. "CN-2026-0003".
    func nextConsentNumber() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let count = consents.count + 1
        return "CN-\(year)-\(String(format: "%04d", count))"
    }

    // MARK: - Settings

    func saveSettings(_ newSettings: AppSettings) {
        settings = newSettings
    }

    /// Bumps the consent text version when the template text changes.
    func updateConsentTemplate(_ text: String) {
        guard text != settings.consentTemplate else { return }
        var updated = settings
        updated.consentTemplate = text
        let current = Int(settings.consentTextVersion) ?? 1
        updated.consentTextVersion = String(current + 1)
        saveSettings(updated)
    }

    // MARK: - CSV export (revenue / sessions for a period)

    /// Machine CSV: fixed dot-decimal, comma separator, UTF-8 with BOM, regardless of UI locale.
    func exportSessionsCSV(period: ExportPeriod = .all) throws -> URL {
        let rows = sessionExportRows(period: period)
        let body = rows.map { $0.map(Self.csvEscape).joined(separator: ",") }.joined(separator: "\r\n")
        let bom = "\u{FEFF}"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GroomCard-Sessions-\(Int(Date().timeIntervalSince1970)).csv")
        try (bom + body).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func sessionExportRows(period: ExportPeriod) -> [[String]] {
        let lowerBound = period.startDate
        let scoped = sessions
            .filter { session in lowerBound.map { $0 <= session.date } ?? true }
            .sorted { $0.date < $1.date }
        let header = [
            "session_id", "date", "pet_name", "breed", "owner_name",
            "style", "has_before", "has_after", "price", "currency",
            "recommendations", "notes"
        ]
        let dataRows: [[String]] = scoped.map { session in
            let pet = pet(id: session.petId)
            let owner = owner(id: pet?.ownerId)
            return [
                session.id.uuidString,
                Self.csvDateFormatter.string(from: session.date),
                pet?.name ?? "",
                pet?.breed ?? "",
                owner?.name ?? "",
                session.style,
                session.hasBefore ? "1" : "0",
                session.hasAfter ? "1" : "0",
                session.price.map { Self.decimalString($0) } ?? "",
                session.currencyCode,
                session.recommendations,
                session.notes
            ]
        }
        return [header] + dataRows
    }

    /// Total revenue for a period as a Decimal (sessions with a price).
    func totalRevenue(period: ExportPeriod) -> Decimal {
        let lowerBound = period.startDate
        return sessions
            .filter { session in lowerBound.map { $0 <= session.date } ?? true }
            .reduce(Decimal(0)) { $0 + ($1.price ?? 0) }
    }

    // MARK: - StoreKit pro entitlement

    func refreshProEntitlement() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.proProductIDSet.contains(transaction.productID) {
                hasPro = true
                break
            }
        }
        setPro(hasPro)
    }

    func grantPro() {
        setPro(true)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            seedDefaultData()
            return
        }
        isLoading = true
        defer { isLoading = false }
        if let payload = try? JSONDecoder().decode(StorePayload.self, from: data) {
            owners = payload.owners
            pets = payload.pets
            sessions = payload.sessions
            consents = payload.consents
            photos = payload.photos
            settings = payload.settings
        }
    }

    private func save() {
        do {
            let payload = StorePayload(
                owners: owners,
                pets: pets,
                sessions: sessions,
                consents: consents,
                photos: photos,
                settings: settings
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Seeds a single example owner + pet on first run so the lists are not empty.
    private func seedDefaultData() {
        let owner = Owner(name: "Jane Doe", phone: "+1 555 0142", email: "jane@example.com")
        let pet = Pet(
            name: "Bella",
            species: .dog,
            breed: "Poodle",
            coatType: .curly,
            behaviorFlags: [.anxious],
            ownerId: owner.id,
            stylePreference: "Teddy bear cut"
        )
        owners = [owner]
        pets = [pet]
    }

    // MARK: - StoreKit plumbing

    private func startEntitlementRefresh() {
        entitlementTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshProEntitlement()
            for await result in Transaction.updates {
                await self.handleTransactionUpdate(result)
            }
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            if case .unverified(let transaction, _) = result {
                await transaction.finish()
            }
            await refreshProEntitlement()
            return
        }
        if Self.proProductIDSet.contains(transaction.productID) {
            if transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                setPro(true)
            } else {
                await refreshProEntitlement()
            }
        }
        await transaction.finish()
    }

    private func setPro(_ isPro: Bool) {
        guard settings.isPro != isPro else { return }
        var updatedSettings = settings
        updatedSettings.isPro = isPro
        saveSettings(updatedSettings)
    }

    // MARK: - Helpers

    private static func decimalString(_ value: Decimal) -> String {
        // Fixed dot-decimal, locale-independent, for machine CSV.
        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 2, .plain)
        return NSDecimalNumber(decimal: rounded).description
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\r") || value.contains("\n") else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

private struct StorePayload: Codable {
    var owners: [Owner]
    var pets: [Pet]
    var sessions: [GroomSession]
    var consents: [Consent]
    var photos: [PhotoAsset]
    var settings: AppSettings
}
