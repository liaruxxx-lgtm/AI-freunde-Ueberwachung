import Combine
import Foundation

// MARK: - Shared repository paths

public enum LibraryPaths {
    private static let dataDirectoryName = "FreundeblickData"

    /// Resolves the shared, local-first repository used by both the app and external tools.
    ///
    /// Resolution order:
    /// 1. `FREUNDEBLICK_DATA_DIR`
    /// 2. The path embedded in this local app build
    /// 3. A repository found from the current working directory
    /// 4. A repository found by walking upwards from the app bundle
    /// 5. Application Support
    public static var dataDirectory: URL {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["FREUNDEBLICK_DATA_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }

        if let embedded = Bundle.main.object(
            forInfoDictionaryKey: "FreundeblickDataDirectory"
        ) as? String,
           !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: embedded, isDirectory: true).standardizedFileURL
        }

        let currentDirectory = URL(
            fileURLWithPath: fileManager.currentDirectoryPath,
            isDirectory: true
        )
        if let repository = repositoryDataDirectory(startingAt: currentDirectory) {
            return repository
        }

        if let repository = repositoryDataDirectory(
            startingAt: Bundle.main.bundleURL.deletingLastPathComponent()
        ) {
            return repository
        }

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
            .standardizedFileURL
    }

    public static var databaseURL: URL {
        dataDirectory.appendingPathComponent("friends.json", isDirectory: false)
    }

    public static var mediaDirectory: URL {
        dataDirectory.appendingPathComponent("Media", isDirectory: true)
    }

    private static func repositoryDataDirectory(startingAt startURL: URL) -> URL? {
        let fileManager = FileManager.default
        var directory = startURL.standardizedFileURL

        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent(dataDirectoryName, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate.standardizedFileURL
            }

            let packageManifest = directory.appendingPathComponent("Package.swift").path
            let gitDirectory = directory.appendingPathComponent(".git").path
            if fileManager.fileExists(atPath: packageManifest)
                || fileManager.fileExists(atPath: gitDirectory) {
                return candidate.standardizedFileURL
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        return nil
    }
}

// MARK: - Store

public enum LibraryStoreError: LocalizedError {
    case emptyPersonName
    case personNotFound(UUID)
    case relationshipNotFound(UUID)
    case relationshipPairNotFound
    case mediaNotFound(UUID)
    case observationNotFound(UUID)
    case groupNotFound(UUID)
    case selfRelationship
    case avatarRequiresImage
    case avatarNotAssignedToPerson
    case unsupportedMedia(URL)
    case invalidProfileLink(String)
    case invalidSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyPersonName:
            "Der Name darf nicht leer sein."
        case let .personNotFound(id):
            "Die Person \(id.uuidString) wurde nicht gefunden."
        case let .relationshipNotFound(id):
            "Die Beziehung \(id.uuidString) wurde nicht gefunden."
        case .relationshipPairNotFound:
            "Die Verbindung zwischen diesen Personen wurde nicht gefunden."
        case let .mediaNotFound(id):
            "Das Medium \(id.uuidString) wurde nicht gefunden."
        case let .observationNotFound(id):
            "Die Beobachtung \(id.uuidString) wurde nicht gefunden."
        case let .groupNotFound(id):
            "Die Gruppe \(id.uuidString) wurde nicht gefunden."
        case .selfRelationship:
            "Eine Person kann keine gerichtete Beziehung zu sich selbst eintragen."
        case .avatarRequiresImage:
            "Als Profilbild kann nur ein Bild verwendet werden."
        case .avatarNotAssignedToPerson:
            "Das ausgewählte Bild ist dieser Person nicht zugeordnet."
        case let .unsupportedMedia(url):
            "\(url.lastPathComponent) ist kein unterstütztes Bild oder Video."
        case let .invalidProfileLink(value):
            "Der Link „\(value)“ ist keine gültige öffentliche HTTPS-Adresse."
        case let .invalidSchemaVersion(version):
            "Die Datenbankversion \(version) ist neuer als diese App unterstützt."
        }
    }
}

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var data: LibraryData
    @Published public private(set) var lastError: String?
    @Published public var presentNewPersonSheet = false

    public let databaseURL: URL
    public let mediaDirectory: URL

    public var people: [Person] { data.people }
    public var relationshipClaims: [RelationshipClaim] { data.relationshipClaims }
    public var mediaItems: [MediaItem] { data.media }
    public var observations: [Observation] { data.observations }
    public var groups: [Group] { data.groups }
    public var inferredGroups: [Group] {
        data.groups.filter { $0.status == .inferred }
    }

    /// Creates a store and immediately loads the shared JSON file. A missing file is initialized.
    ///
    /// Pass a custom `databaseURL` in tests or for an explicitly selected library.
    public init(
        databaseURL: URL = LibraryPaths.databaseURL,
        mediaDirectory: URL? = nil,
        seedDemoData: Bool = false
    ) {
        self.databaseURL = databaseURL.standardizedFileURL
        self.mediaDirectory = (
            mediaDirectory
                ?? databaseURL.deletingLastPathComponent()
                    .appendingPathComponent("Media", isDirectory: true)
        ).standardizedFileURL
        self.data = LibraryData()

        do {
            try ensureRepositoryDirectories()

            if FileManager.default.fileExists(atPath: self.databaseURL.path) {
                self.data = try Self.decodeLibrary(at: self.databaseURL)
                guard self.data.schemaVersion <= LibraryData.currentSchemaVersion else {
                    throw LibraryStoreError.invalidSchemaVersion(self.data.schemaVersion)
                }
                refreshInferredFriendshipGroups()
            } else {
                self.data = seedDemoData ? Self.demoLibrary() : LibraryData()
                refreshInferredFriendshipGroups()
                try save()
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: Persistence

    public func reload() throws {
        do {
            let loaded = try Self.decodeLibrary(at: databaseURL)
            guard loaded.schemaVersion <= LibraryData.currentSchemaVersion else {
                throw LibraryStoreError.invalidSchemaVersion(loaded.schemaVersion)
            }
            data = loaded
            refreshInferredFriendshipGroups()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Encodes the complete library and atomically replaces `friends.json`.
    public func save() throws {
        do {
            try ensureRepositoryDirectories()
            data.schemaVersion = LibraryData.currentSchemaVersion
            data.lastUpdated = Date()

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let encoded = try encoder.encode(data)
            try encoded.write(to: databaseURL, options: [.atomic])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private static func decodeLibrary(at url: URL) throws -> LibraryData {
        let encoded = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryData.self, from: encoded)
    }

    private func ensureRepositoryDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: mediaDirectory,
            withIntermediateDirectories: true
        )
    }

    private func transaction(
        reinferGroups: Bool = false,
        _ mutation: () throws -> Void
    ) throws {
        let previous = data
        do {
            try mutation()
            if reinferGroups {
                refreshInferredFriendshipGroups()
            }
            try save()
        } catch {
            data = previous
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: People CRUD

    public func person(id: UUID) -> Person? {
        data.people.first { $0.id == id }
    }

    public func addPerson(_ person: Person) throws {
        try validate(person)
        try transaction(reinferGroups: true) {
            if let index = data.people.firstIndex(where: { $0.id == person.id }) {
                data.people[index] = person
            } else {
                data.people.append(person)
            }
        }
    }

    @discardableResult
    public func addPerson(
        name: String,
        aliases: [String] = [],
        birthday: Date? = nil,
        location: String? = nil,
        summary: String = "",
        temperamentTags: [String] = [],
        interests: [String] = [],
        profileDetails: [String: [String]] = [:],
        links: [ProfileLink] = []
    ) throws -> Person {
        let person = Person(
            name: name,
            aliases: aliases,
            birthday: birthday,
            location: location,
            summary: summary,
            temperamentTags: temperamentTags,
            interests: interests,
            profileDetails: profileDetails,
            links: links
        )
        try addPerson(person)
        return person
    }

    public func updatePerson(_ person: Person) throws {
        try validate(person)
        guard data.people.contains(where: { $0.id == person.id }) else {
            throw LibraryStoreError.personNotFound(person.id)
        }
        try transaction(reinferGroups: true) {
            guard let index = data.people.firstIndex(where: { $0.id == person.id }) else {
                throw LibraryStoreError.personNotFound(person.id)
            }
            data.people[index] = person
        }
    }

    public func deletePerson(id: UUID) throws {
        guard data.people.contains(where: { $0.id == id }) else {
            throw LibraryStoreError.personNotFound(id)
        }

        try transaction(reinferGroups: true) {
            data.people.removeAll { $0.id == id }
            data.relationshipClaims.removeAll {
                $0.fromPersonID == id || $0.toPersonID == id
            }
            data.observations.removeAll { $0.personID == id }

            for mediaIndex in data.media.indices {
                data.media[mediaIndex].personIDs.removeAll { $0 == id }
            }

            for personIndex in data.people.indices
            where data.people[personIndex].avatarMediaID != nil {
                if let avatarID = data.people[personIndex].avatarMediaID,
                   !data.media.contains(where: {
                       $0.id == avatarID && $0.personIDs.contains(data.people[personIndex].id)
                   }) {
                    data.people[personIndex].avatarMediaID = nil
                }
            }

            for groupIndex in data.groups.indices {
                data.groups[groupIndex].memberIDs.removeAll { $0 == id }
            }
            data.groups.removeAll {
                $0.status != .inferred && $0.memberIDs.count < 2
            }
        }
    }

    private func validate(_ person: Person) throws {
        if person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LibraryStoreError.emptyPersonName
        }
        for link in person.links {
            guard let url = link.resolvedURL,
                  PublicWebResearchService.isSafePublicPageURL(url)
            else {
                throw LibraryStoreError.invalidProfileLink(link.url)
            }
        }
    }

    // MARK: Relationship claims CRUD

    public func addRelationshipClaim(_ claim: RelationshipClaim) throws {
        try validate(claim)
        try transaction(reinferGroups: true) {
            if let index = data.relationshipClaims.firstIndex(where: { $0.id == claim.id }) {
                data.relationshipClaims[index] = claim
            } else {
                data.relationshipClaims.append(claim)
            }
        }
    }

    @discardableResult
    public func addRelationshipClaim(
        from fromPersonID: UUID,
        to toPersonID: UUID,
        kind: RelationshipKind = .friendship,
        familyRole: FamilyRelationshipRole? = nil,
        status: RelationshipStatus = .claimed,
        source: EvidenceSource = .personStatement,
        notes: String = ""
    ) throws -> RelationshipClaim {
        let claim = RelationshipClaim(
            fromPersonID: fromPersonID,
            toPersonID: toPersonID,
            kind: kind,
            familyRole: familyRole,
            status: status,
            source: source,
            notes: notes
        )
        try addRelationshipClaim(claim)
        return claim
    }

    public func updateRelationshipClaim(_ claim: RelationshipClaim) throws {
        try validate(claim)
        guard data.relationshipClaims.contains(where: { $0.id == claim.id }) else {
            throw LibraryStoreError.relationshipNotFound(claim.id)
        }
        try transaction(reinferGroups: true) {
            guard let index = data.relationshipClaims.firstIndex(where: { $0.id == claim.id })
            else {
                throw LibraryStoreError.relationshipNotFound(claim.id)
            }
            data.relationshipClaims[index] = claim
        }
    }

    public func deleteRelationshipClaim(id: UUID) throws {
        guard data.relationshipClaims.contains(where: { $0.id == id }) else {
            throw LibraryStoreError.relationshipNotFound(id)
        }
        try transaction(reinferGroups: true) {
            data.relationshipClaims.removeAll { $0.id == id }
        }
    }

    /// Replaces one pairwise relationship in a single transaction.
    ///
    /// A mutual relationship is persisted as two directed claims so automatic
    /// friendship-group detection can still explain how it reached its result.
    @discardableResult
    public func setRelationshipPair(
        from fromPersonID: UUID,
        to toPersonID: UUID,
        kind: RelationshipKind,
        familyRole: FamilyRelationshipRole? = nil,
        mutual: Bool,
        notes: String = "",
        source: EvidenceSource = .manual,
        replacingKind: RelationshipKind? = nil
    ) throws -> [RelationshipClaim] {
        let forward = RelationshipClaim(
            fromPersonID: fromPersonID,
            toPersonID: toPersonID,
            kind: kind,
            familyRole: kind == .family ? familyRole : nil,
            source: source,
            notes: notes
        )
        try validate(forward)

        var replacements = [forward]
        if mutual {
            let reverse = RelationshipClaim(
                fromPersonID: toPersonID,
                toPersonID: fromPersonID,
                kind: kind,
                familyRole: kind == .family ? (familyRole ?? .familyMember).inverse : nil,
                source: source,
                notes: notes
            )
            try validate(reverse)
            replacements.append(reverse)
        }

        let kindsToReplace = Set([kind, replacingKind].compactMap { $0 })
        try transaction(reinferGroups: true) {
            data.relationshipClaims.removeAll { claim in
                let isSamePair =
                    (claim.fromPersonID == fromPersonID && claim.toPersonID == toPersonID)
                    || (claim.fromPersonID == toPersonID && claim.toPersonID == fromPersonID)
                return isSamePair && kindsToReplace.contains(claim.kind)
            }
            data.relationshipClaims.append(contentsOf: replacements)
        }
        return replacements
    }

    public func deleteRelationshipPair(
        between firstPersonID: UUID,
        and secondPersonID: UUID,
        kind: RelationshipKind
    ) throws {
        let matchingIDs = data.relationshipClaims.filter { claim in
            let isSamePair =
                (claim.fromPersonID == firstPersonID && claim.toPersonID == secondPersonID)
                || (claim.fromPersonID == secondPersonID && claim.toPersonID == firstPersonID)
            return isSamePair && claim.kind == kind
        }
        guard !matchingIDs.isEmpty else {
            throw LibraryStoreError.relationshipPairNotFound
        }

        try transaction(reinferGroups: true) {
            data.relationshipClaims.removeAll { claim in
                let isSamePair =
                    (claim.fromPersonID == firstPersonID && claim.toPersonID == secondPersonID)
                    || (claim.fromPersonID == secondPersonID && claim.toPersonID == firstPersonID)
                return isSamePair && claim.kind == kind
            }
        }
    }

    private func validate(_ claim: RelationshipClaim) throws {
        guard claim.fromPersonID != claim.toPersonID else {
            throw LibraryStoreError.selfRelationship
        }
        guard person(id: claim.fromPersonID) != nil else {
            throw LibraryStoreError.personNotFound(claim.fromPersonID)
        }
        guard person(id: claim.toPersonID) != nil else {
            throw LibraryStoreError.personNotFound(claim.toPersonID)
        }
    }

    // MARK: Media CRUD and import

    public func media(for personID: UUID) -> [MediaItem] {
        data.media
            .filter { $0.personIDs.contains(personID) }
            .sorted { ($0.capturedAt ?? $0.importedAt) > ($1.capturedAt ?? $1.importedAt) }
    }

    public func mediaItem(id: UUID) -> MediaItem? {
        data.media.first { $0.id == id }
    }

    public func mediaURL(for item: MediaItem) -> URL {
        // Persisted metadata may also be written by an external tool. Restrict it to
        // a single filename so a malformed `../../…` value can never escape Media/.
        let safeFilename = URL(fileURLWithPath: item.storedFilename).lastPathComponent
        return mediaDirectory.appendingPathComponent(safeFilename, isDirectory: false)
    }

    public func setAvatarMediaID(_ mediaID: UUID?, for personID: UUID) throws {
        guard person(id: personID) != nil else {
            throw LibraryStoreError.personNotFound(personID)
        }

        if let mediaID {
            guard let item = mediaItem(id: mediaID) else {
                throw LibraryStoreError.mediaNotFound(mediaID)
            }
            guard item.kind == .image else {
                throw LibraryStoreError.avatarRequiresImage
            }
            guard item.personIDs.contains(personID) else {
                throw LibraryStoreError.avatarNotAssignedToPerson
            }
        }

        try transaction {
            guard let personIndex = data.people.firstIndex(where: { $0.id == personID })
            else {
                throw LibraryStoreError.personNotFound(personID)
            }
            data.people[personIndex].avatarMediaID = mediaID
        }
    }

    @discardableResult
    public func importCroppedProfileImage(
        pngData: Data,
        originalFilename: String,
        for personID: UUID
    ) throws -> MediaItem {
        guard person(id: personID) != nil else {
            throw LibraryStoreError.personNotFound(personID)
        }
        try ensureRepositoryDirectories()

        let previous = data
        let storedFilename = "\(UUID().uuidString.lowercased())-profile.png"
        let destination = mediaDirectory
            .appendingPathComponent(storedFilename, isDirectory: false)
        let temporary = mediaDirectory
            .appendingPathComponent(".crop-\(UUID().uuidString)", isDirectory: false)
        let cleanOriginalName = originalFilename
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayFilename = cleanOriginalName.isEmpty
            ? "Profilbild-Zuschnitt.png"
            : "\(URL(fileURLWithPath: cleanOriginalName).deletingPathExtension().lastPathComponent)-Profilbild.png"
        let item = MediaItem(
            storedFilename: storedFilename,
            originalFilename: displayFilename,
            kind: .image,
            personIDs: [personID],
            tags: ["Profilbild-Zuschnitt"],
            notes: "Quadratischer Profilbild-Zuschnitt; das ursprüngliche Bild wurde nicht verändert."
        )

        do {
            try pngData.write(to: temporary)
            try FileManager.default.moveItem(at: temporary, to: destination)
            data.media.append(item)
            guard let personIndex = data.people.firstIndex(where: { $0.id == personID })
            else {
                throw LibraryStoreError.personNotFound(personID)
            }
            data.people[personIndex].avatarMediaID = item.id
            try save()
            return item
        } catch {
            data = previous
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: destination)
            lastError = error.localizedDescription
            throw error
        }
    }

    public func addMedia(_ item: MediaItem) throws {
        try validatePersonReferences(item.personIDs)
        try transaction {
            if let index = data.media.firstIndex(where: { $0.id == item.id }) {
                data.media[index] = item
            } else {
                data.media.append(item)
            }
        }
    }

    public func updateMedia(_ item: MediaItem) throws {
        try validatePersonReferences(item.personIDs)
        guard data.media.contains(where: { $0.id == item.id }) else {
            throw LibraryStoreError.mediaNotFound(item.id)
        }
        try transaction {
            guard let index = data.media.firstIndex(where: { $0.id == item.id }) else {
                throw LibraryStoreError.mediaNotFound(item.id)
            }
            data.media[index] = item
        }
    }

    public func deleteMedia(id: UUID, deleteStoredFile: Bool = false) throws {
        guard let item = mediaItem(id: id) else {
            throw LibraryStoreError.mediaNotFound(id)
        }

        try transaction {
            data.media.removeAll { $0.id == id }
            data.observations = data.observations.map { observation in
                var updated = observation
                updated.evidenceMediaIDs.removeAll { $0 == id }
                return updated
            }
            for index in data.people.indices where data.people[index].avatarMediaID == id {
                data.people[index].avatarMediaID = nil
            }
        }

        if deleteStoredFile {
            let fileURL = mediaURL(for: item)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    /// Copies selected files into the local media repository before atomically saving metadata.
    @discardableResult
    public func importMedia(
        from urls: [URL],
        personIDs: [UUID] = []
    ) throws -> [MediaItem] {
        try validatePersonReferences(personIDs)
        try ensureRepositoryDirectories()

        let previous = data
        var copiedURLs: [URL] = []
        var imported: [MediaItem] = []

        do {
            for sourceURL in urls {
                let kind = try Self.mediaKind(for: sourceURL)
                let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if scopedAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let fileExtension = sourceURL.pathExtension.lowercased()
                let storedFilename = UUID().uuidString.lowercased()
                    + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
                let destination = mediaDirectory
                    .appendingPathComponent(storedFilename, isDirectory: false)
                let temporary = mediaDirectory
                    .appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: false)

                try FileManager.default.copyItem(at: sourceURL, to: temporary)
                try FileManager.default.moveItem(at: temporary, to: destination)
                copiedURLs.append(destination)

                let resourceValues = try? sourceURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                )
                imported.append(
                    MediaItem(
                        storedFilename: storedFilename,
                        originalFilename: sourceURL.lastPathComponent,
                        kind: kind,
                        personIDs: personIDs,
                        capturedAt: resourceValues?.contentModificationDate
                    )
                )
            }

            data.media.append(contentsOf: imported)
            try save()
            return imported
        } catch {
            data = previous
            for copiedURL in copiedURLs {
                try? FileManager.default.removeItem(at: copiedURL)
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    private static func mediaKind(for url: URL) throws -> MediaKind {
        let imageExtensions: Set<String> = [
            "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
        ]
        let videoExtensions: Set<String> = [
            "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm"
        ]
        let fileExtension = url.pathExtension.lowercased()
        if imageExtensions.contains(fileExtension) {
            return .image
        }
        if videoExtensions.contains(fileExtension) {
            return .video
        }
        throw LibraryStoreError.unsupportedMedia(url)
    }

    // MARK: Observations CRUD

    public func observations(for personID: UUID) -> [Observation] {
        data.observations
            .filter { $0.personID == personID && $0.status.isVisibleByDefault }
            .sorted {
                if $0.confidence == $1.confidence {
                    return $0.createdAt > $1.createdAt
                }
                return $0.confidence > $1.confidence
            }
    }

    public func addObservation(_ observation: Observation) throws {
        try validate(observation)
        try transaction {
            if let index = data.observations.firstIndex(where: { $0.id == observation.id }) {
                data.observations[index] = observation
            } else {
                data.observations.append(observation)
            }
        }
    }

    public func updateObservation(_ observation: Observation) throws {
        try validate(observation)
        guard data.observations.contains(where: { $0.id == observation.id }) else {
            throw LibraryStoreError.observationNotFound(observation.id)
        }
        try transaction {
            guard let index = data.observations.firstIndex(where: { $0.id == observation.id })
            else {
                throw LibraryStoreError.observationNotFound(observation.id)
            }
            data.observations[index] = observation
        }
    }

    public func deleteObservation(id: UUID) throws {
        guard data.observations.contains(where: { $0.id == id }) else {
            throw LibraryStoreError.observationNotFound(id)
        }
        try transaction {
            data.observations.removeAll { $0.id == id }
        }
    }

    private func validate(_ observation: Observation) throws {
        guard person(id: observation.personID) != nil else {
            throw LibraryStoreError.personNotFound(observation.personID)
        }
        let mediaIDs = Set(data.media.map(\.id))
        if let missingID = observation.evidenceMediaIDs.first(where: { !mediaIDs.contains($0) }) {
            throw LibraryStoreError.mediaNotFound(missingID)
        }
    }

    private func validatePersonReferences(_ ids: [UUID]) throws {
        let knownIDs = Set(data.people.map(\.id))
        if let missingID = ids.first(where: { !knownIDs.contains($0) }) {
            throw LibraryStoreError.personNotFound(missingID)
        }
    }

    // MARK: Manual groups CRUD

    public func addGroup(_ group: Group) throws {
        try validatePersonReferences(group.memberIDs)
        try transaction(reinferGroups: true) {
            if let index = data.groups.firstIndex(where: { $0.id == group.id }) {
                data.groups[index] = group
            } else {
                data.groups.append(group)
            }
        }
    }

    public func updateGroup(_ group: Group) throws {
        try validatePersonReferences(group.memberIDs)
        guard data.groups.contains(where: { $0.id == group.id }) else {
            throw LibraryStoreError.groupNotFound(group.id)
        }
        try transaction(reinferGroups: true) {
            guard let index = data.groups.firstIndex(where: { $0.id == group.id }) else {
                throw LibraryStoreError.groupNotFound(group.id)
            }
            data.groups[index] = group
        }
    }

    public func deleteGroup(id: UUID) throws {
        guard data.groups.contains(where: { $0.id == id }) else {
            throw LibraryStoreError.groupNotFound(id)
        }
        try transaction(reinferGroups: true) {
            data.groups.removeAll { $0.id == id }
        }
    }

    // MARK: Friendship graph and maximal cliques

    public func mutualRelationshipIDs(
        for personID: UUID,
        kind: RelationshipKind
    ) -> [UUID] {
        guard person(id: personID) != nil else { return [] }
        let activeClaims = data.relationshipClaims.filter {
            $0.kind == kind && $0.status.supportsInference
        }
        let outgoing = Set(
            activeClaims
                .filter { $0.fromPersonID == personID }
                .map(\.toPersonID)
        )
        let incoming = Set(
            activeClaims
                .filter { $0.toPersonID == personID }
                .map(\.fromPersonID)
        )
        return outgoing.intersection(incoming).sorted {
            (person(id: $0)?.name ?? "") < (person(id: $1)?.name ?? "")
        }
    }

    public func mutualFriendIDs(for personID: UUID) -> [UUID] {
        mutualRelationshipIDs(for: personID, kind: .friendship)
    }

    public func mutualFamilyIDs(for personID: UUID) -> [UUID] {
        mutualRelationshipIDs(for: personID, kind: .family)
    }

    public func pendingFamilyIDs(for personID: UUID) -> [UUID] {
        guard person(id: personID) != nil else { return [] }
        let activeClaims = data.relationshipClaims.filter {
            $0.kind == .family
                && $0.status.supportsInference
                && ($0.fromPersonID == personID || $0.toPersonID == personID)
        }
        let connected = Set(activeClaims.map {
            $0.fromPersonID == personID ? $0.toPersonID : $0.fromPersonID
        })
        let mutual = Set(mutualFamilyIDs(for: personID))
        return connected.subtracting(mutual).sorted {
            (person(id: $0)?.name ?? "") < (person(id: $1)?.name ?? "")
        }
    }

    public func familyRole(from personID: UUID, to otherPersonID: UUID) -> FamilyRelationshipRole? {
        if let outgoing = data.relationshipClaims
            .filter({
                $0.fromPersonID == personID
                    && $0.toPersonID == otherPersonID
                    && $0.kind == .family
                    && $0.status.supportsInference
            })
            .max(by: { $0.createdAt < $1.createdAt }) {
            return outgoing.familyRole
        }

        return data.relationshipClaims
            .filter({
                $0.fromPersonID == otherPersonID
                    && $0.toPersonID == personID
                    && $0.kind == .family
                    && $0.status.supportsInference
            })
            .max(by: { $0.createdAt < $1.createdAt })?
            .familyRole?
            .inverse
    }

    /// Rebuilds and saves all automatically inferred friendship groups.
    @discardableResult
    public func inferFriendshipGroups() throws -> [Group] {
        let previous = data
        do {
            refreshInferredFriendshipGroups()
            try save()
            return inferredGroups
        } catch {
            data = previous
            lastError = error.localizedDescription
            throw error
        }
    }

    private func refreshInferredFriendshipGroups() {
        let previousGroups = data.groups.filter { $0.status == .inferred }
        let manualGroups = data.groups.filter { $0.status != .inferred }
        let graph = mutualFriendshipGraph()
        let cliques = maximalCliques(in: graph)
            .filter { $0.count >= 3 }
            .filter { clique in
                !manualGroups.contains { Set($0.memberIDs) == clique }
            }
            .sorted { lhs, rhs in
                let left = lhs.map(\.uuidString).sorted().joined()
                let right = rhs.map(\.uuidString).sorted().joined()
                return left < right
            }

        let rebuilt = cliques.map { clique -> Group in
            let sortedIDs = clique.sorted {
                (person(id: $0)?.name ?? "") < (person(id: $1)?.name ?? "")
            }
            let existing = previousGroups.first {
                Set($0.memberIDs) == Set(sortedIDs)
            }
            let names = sortedIDs.compactMap { person(id: $0)?.name }
            let name = "Freundesgruppe: \(Self.germanList(names))"
            return Group(
                id: existing?.id ?? UUID(),
                name: name,
                memberIDs: sortedIDs,
                status: .inferred,
                confidence: inferredConfidence(for: sortedIDs),
                explanation: "Alle Mitglieder haben sich jeweils gegenseitig als befreundet angegeben.",
                createdAt: existing?.createdAt ?? Date()
            )
        }

        data.groups = manualGroups + rebuilt
    }

    private func mutualFriendshipGraph() -> [UUID: Set<UUID>] {
        let personIDs = Set(data.people.map(\.id))
        let activeClaims = data.relationshipClaims.filter {
            $0.kind == .friendship
                && $0.status.supportsInference
                && personIDs.contains($0.fromPersonID)
                && personIDs.contains($0.toPersonID)
        }

        var directed: [UUID: Set<UUID>] = [:]
        for claim in activeClaims {
            directed[claim.fromPersonID, default: []].insert(claim.toPersonID)
        }

        var graph = Dictionary(uniqueKeysWithValues: personIDs.map { ($0, Set<UUID>()) })
        for source in personIDs {
            for target in directed[source, default: []]
            where directed[target, default: []].contains(source) {
                graph[source, default: []].insert(target)
                graph[target, default: []].insert(source)
            }
        }
        return graph
    }

    private func maximalCliques(in graph: [UUID: Set<UUID>]) -> [Set<UUID>] {
        var result: [Set<UUID>] = []

        func visit(_ current: Set<UUID>, _ candidates: Set<UUID>, _ excluded: Set<UUID>) {
            if candidates.isEmpty && excluded.isEmpty {
                result.append(current)
                return
            }

            let pivot = candidates.union(excluded).max {
                graph[$0, default: []].intersection(candidates).count
                    < graph[$1, default: []].intersection(candidates).count
            }
            let pivotNeighbours = pivot.map { graph[$0, default: []] } ?? []
            var remaining = candidates
            var visited = excluded

            for vertex in candidates.subtracting(pivotNeighbours) {
                let neighbours = graph[vertex, default: []]
                visit(
                    current.union([vertex]),
                    remaining.intersection(neighbours),
                    visited.intersection(neighbours)
                )
                remaining.remove(vertex)
                visited.insert(vertex)
            }
        }

        visit([], Set(graph.keys), [])
        return result
    }

    private func inferredConfidence(for memberIDs: [UUID]) -> Double {
        guard memberIDs.count >= 2 else { return 0 }
        var pairScores: [Double] = []

        for leftIndex in memberIDs.indices {
            for rightIndex in memberIDs.indices where rightIndex > leftIndex {
                let left = memberIDs[leftIndex]
                let right = memberIDs[rightIndex]
                let forward = bestFriendshipClaim(from: left, to: right)
                let backward = bestFriendshipClaim(from: right, to: left)
                guard let forward, let backward else { continue }
                pairScores.append(
                    min(Self.claimConfidence(forward), Self.claimConfidence(backward))
                )
            }
        }

        return pairScores.min() ?? 0
    }

    private func bestFriendshipClaim(from: UUID, to: UUID) -> RelationshipClaim? {
        data.relationshipClaims
            .filter {
                $0.fromPersonID == from
                    && $0.toPersonID == to
                    && $0.kind == .friendship
                    && $0.status.supportsInference
            }
            .max {
                Self.claimConfidence($0) < Self.claimConfidence($1)
            }
    }

    private static func claimConfidence(_ claim: RelationshipClaim) -> Double {
        switch claim.status {
        case .confirmed: 1
        case .claimed: claim.source == .personStatement ? 0.9 : 0.75
        case .disputed: 0.35
        case .rejected, .ended: 0
        }
    }

    // MARK: German natural-language questions

    public func answer(_ question: String) -> QueryAnswer {
        let normalizedQuestion = Self.normalized(question)
        let mentionedPeople = peopleMentioned(in: normalizedQuestion)

        if mentionedPeople.count > 1 {
            return QueryAnswer(
                kind: .notFound,
                title: "Der Name ist mehrdeutig",
                subtitle: "Mehrere Profile passen: \(Self.germanList(mentionedPeople.map(\.name))). Bitte nenne den vollständigen Namen."
            )
        }

        if let matchedPerson = mentionedPeople.first {
            if normalizedQuestion.contains("wie alt")
                || normalizedQuestion.contains("alter")
                || normalizedQuestion.contains("geburt") {
                return ageAnswer(for: matchedPerson)
            }

            if normalizedQuestion.contains("wo wohn")
                || normalizedQuestion.contains("wohnt")
                || normalizedQuestion.contains("wo wont")
                || normalizedQuestion.contains("wo leb")
                || normalizedQuestion.contains("wohnort") {
                return locationAnswer(for: matchedPerson)
            }

            if normalizedQuestion.contains("befreundet")
                || normalizedQuestion.contains("freund von")
                || normalizedQuestion.contains("freunde von")
                || normalizedQuestion.contains("freundinnen von") {
                return friendsAnswer(for: matchedPerson)
            }

            if normalizedQuestion.contains("gruppe") {
                return groupsAnswer(for: matchedPerson)
            }

            if normalizedQuestion.contains("social")
                || normalizedQuestion.contains("instagram")
                || normalizedQuestion.contains("tiktok")
                || normalizedQuestion.contains("webseite")
                || normalizedQuestion.contains("website")
                || normalizedQuestion.contains("online")
                || normalizedQuestion.contains("link") {
                return linksAnswer(for: matchedPerson)
            }

            if let detailAnswer = profileDetailAnswer(
                for: matchedPerson,
                question: normalizedQuestion
            ) {
                return detailAnswer
            }

            if normalizedQuestion.contains("gemut")
                || normalizedQuestion.contains("charakter")
                || normalizedQuestion.contains("personlichkeit")
                || normalizedQuestion.contains("ruhig")
                || normalizedQuestion.contains("wie ist") {
                return personalityAnswer(for: matchedPerson)
            }

            if normalizedQuestion.contains("tragt")
                || normalizedQuestion.contains("kleidung")
                || normalizedQuestion.contains("outfit")
                || normalizedQuestion.contains("stil")
                || normalizedQuestion.contains("anzieht") {
                return clothingAnswer(for: matchedPerson)
            }

            if normalizedQuestion.contains("foto")
                || normalizedQuestion.contains("bild")
                || normalizedQuestion.contains("video")
                || normalizedQuestion.contains("medien") {
                return mediaAnswer(for: matchedPerson)
            }

            return overviewAnswer(for: matchedPerson)
        }

        if normalizedQuestion.contains("gruppe") {
            let visibleGroups = data.groups.filter { $0.status.isVisible }
            return QueryAnswer(
                kind: .groups,
                title: "Freundesgruppen",
                subtitle: visibleGroups.isEmpty
                    ? "Noch keine Gruppe erkannt."
                    : "\(visibleGroups.count) Gruppe\(visibleGroups.count == 1 ? "" : "n")",
                items: visibleGroups.map {
                    QueryAnswerItem(
                        label: $0.name,
                        value: Self.germanList(
                            $0.memberIDs.compactMap { person(id: $0)?.name }
                        ),
                        symbolName: "person.3.fill",
                        confidence: $0.confidence
                    )
                },
                personIDs: Array(Set(visibleGroups.flatMap(\.memberIDs))),
                groupIDs: visibleGroups.map(\.id)
            )
        }

        let matches = searchPeople(matching: question)
        if !matches.isEmpty {
            return QueryAnswer(
                kind: .searchResults,
                title: "Passende Personen",
                subtitle: "\(matches.count) Treffer",
                personIDs: matches.map(\.id)
            )
        }

        return QueryAnswer(
            kind: .notFound,
            title: "Das konnte ich noch nicht zuordnen",
            subtitle: "Nenne eine Person, zum Beispiel: „Wer ist Leni?“ oder „Mit wem ist Leni befreundet?“"
        )
    }

    public func searchPeople(matching query: String) -> [Person] {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else { return data.people }

        return data.people
            .filter { person in
                person.allNames.contains {
                    let name = Self.normalized($0)
                    return name.contains(normalizedQuery) || normalizedQuery.contains(name)
                }
                || Self.normalized(person.summary).contains(normalizedQuery)
                || person.interests.contains {
                    Self.normalized($0).contains(normalizedQuery)
                }
                || person.links.contains {
                    Self.normalized(
                        [$0.title, $0.handle, $0.url, $0.platform.germanLabel]
                            .joined(separator: " ")
                    ).contains(normalizedQuery)
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func peopleMentioned(in normalizedQuestion: String) -> [Person] {
        let words = Set(normalizedQuestion.split(separator: " ").map(String.init))
        let candidates: [(person: Person, match: String)] = data.people.flatMap { person in
            var names = person.allNames
            let nameParts = person.name.components(separatedBy: .whitespaces)
            if let firstName = nameParts.first, !firstName.isEmpty {
                names.append(firstName)
            }
            return names.map { name in
                (person: person, match: Self.normalized(name))
            }
        }
        .filter { candidate in
            let possessive = candidate.match.hasSuffix("s")
                ? candidate.match
                : candidate.match + "s"
            return !candidate.match.isEmpty
                && (
                    normalizedQuestion == candidate.match
                        || normalizedQuestion.contains(candidate.match + " ")
                        || normalizedQuestion.hasSuffix(" " + candidate.match)
                        || words.contains(candidate.match)
                        || normalizedQuestion == possessive
                        || normalizedQuestion.contains(possessive + " ")
                        || normalizedQuestion.hasSuffix(" " + possessive)
                        || words.contains(possessive)
                )
        }

        guard let longestMatch = candidates.map(\.match.count).max() else {
            return []
        }

        var seen = Set<UUID>()
        return candidates
            .filter { $0.match.count == longestMatch }
            .sorted {
                $0.person.name.localizedCaseInsensitiveCompare($1.person.name)
                    == .orderedAscending
            }
            .compactMap { candidate in
                seen.insert(candidate.person.id).inserted ? candidate.person : nil
            }
    }

    private func overviewAnswer(for person: Person) -> QueryAnswer {
        var items: [QueryAnswerItem] = []
        if !person.summary.isEmpty {
            items.append(
                QueryAnswerItem(
                    label: "Kurzprofil",
                    value: person.summary,
                    symbolName: "person.text.rectangle"
                )
            )
        }
        if let age = person.age() {
            items.append(
                QueryAnswerItem(label: "Alter", value: "\(age) Jahre", symbolName: "birthday.cake")
            )
        }
        if let location = person.location, !location.isEmpty {
            items.append(
                QueryAnswerItem(label: "Wohnort", value: location, symbolName: "mappin.and.ellipse")
            )
        }
        if !person.temperamentTags.isEmpty {
            items.append(
                QueryAnswerItem(
                    label: "Gemüt",
                    value: Self.germanList(person.temperamentTags),
                    symbolName: "sparkles"
                )
            )
        }
        if !person.interests.isEmpty {
            items.append(
                QueryAnswerItem(
                    label: "Interessen",
                    value: Self.germanList(person.interests),
                    symbolName: "heart.text.square"
                )
            )
        }
        for detail in person.profileDetails
            .filter({ !$0.value.isEmpty })
            .sorted(by: {
                ProfileSuggestionCatalog.displayLabel(for: $0.key)
                    .localizedCaseInsensitiveCompare(
                        ProfileSuggestionCatalog.displayLabel(for: $1.key)
                    ) == .orderedAscending
            })
            .prefix(6) {
            let definition = ProfileSuggestionCatalog.definition(for: detail.key)
            items.append(
                QueryAnswerItem(
                    label: ProfileSuggestionCatalog.displayLabel(for: detail.key),
                    value: Self.germanList(detail.value),
                    symbolName: definition?.systemImage ?? "square.and.pencil"
                )
            )
        }
        let confirmedLinks = person.links.filter(\.confirmed)
        if !confirmedLinks.isEmpty {
            items.append(
                QueryAnswerItem(
                    label: "Online",
                    value: Self.germanList(
                        confirmedLinks.map { $0.platform.germanLabel }
                    ),
                    symbolName: "link.circle.fill"
                )
            )
        }

        let friends = mutualFriendIDs(for: person.id)
        if !friends.isEmpty {
            items.append(
                QueryAnswerItem(
                    label: "Befreundet mit",
                    value: Self.germanList(friends.compactMap { self.person(id: $0)?.name }),
                    symbolName: "person.2.fill"
                )
            )
        }

        let personGroups = data.groups.filter {
            $0.status.isVisible && $0.memberIDs.contains(person.id)
        }
        return QueryAnswer(
            kind: .personOverview,
            title: person.name,
            subtitle: person.aliases.isEmpty
                ? nil
                : "Auch bekannt als \(Self.germanList(person.aliases))",
            items: items,
            personIDs: [person.id] + friends,
            mediaIDs: media(for: person.id).map(\.id),
            groupIDs: personGroups.map(\.id)
        )
    }

    private func profileDetailAnswer(
        for person: Person,
        question: String
    ) -> QueryAnswer? {
        let matches = person.profileDetails
            .filter { !$0.value.isEmpty }
            .compactMap { key, values -> (String, [String], String)? in
                let label = ProfileSuggestionCatalog.displayLabel(for: key)
                let normalizedLabel = Self.normalized(label)
                let shorterLabel = normalizedLabel
                    .replacingOccurrences(of: "lieblings", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard question.contains(normalizedLabel)
                        || (!shorterLabel.isEmpty && question.contains(shorterLabel))
                else {
                    return nil
                }
                return (key, values, label)
            }
            .sorted { $0.2.count > $1.2.count }

        guard let (key, values, label) = matches.first else { return nil }
        return QueryAnswer(
            kind: .profileDetail,
            title: "\(label) von \(person.name)",
            subtitle: Self.germanList(values),
            items: [
                QueryAnswerItem(
                    label: label,
                    value: Self.germanList(values),
                    symbolName: ProfileSuggestionCatalog
                        .definition(for: key)?.systemImage
                        ?? "square.and.pencil"
                )
            ],
            personIDs: [person.id]
        )
    }

    private func ageAnswer(for person: Person) -> QueryAnswer {
        guard let age = person.age() else {
            return QueryAnswer(
                kind: .age,
                title: "Alter von \(person.name)",
                subtitle: "Der Geburtstag ist noch nicht eingetragen.",
                personIDs: [person.id]
            )
        }
        return QueryAnswer(
            kind: .age,
            title: "\(person.name) ist \(age) Jahre alt",
            items: [
                QueryAnswerItem(
                    label: "Alter",
                    value: "\(age)",
                    symbolName: "birthday.cake.fill"
                )
            ],
            personIDs: [person.id]
        )
    }

    private func locationAnswer(for person: Person) -> QueryAnswer {
        let locationObservation = observations(for: person.id)
            .first { $0.category == .location }
        let location = person.location ?? locationObservation?.value
        return QueryAnswer(
            kind: .location,
            title: "Wohnort von \(person.name)",
            subtitle: location ?? "Noch kein Wohnort eingetragen.",
            items: location.map {
                [
                    QueryAnswerItem(
                        label: "Wohnort",
                        value: $0,
                        symbolName: "mappin.and.ellipse",
                        confidence: locationObservation?.confidence
                    )
                ]
            } ?? [],
            personIDs: [person.id]
        )
    }

    private func friendsAnswer(for person: Person) -> QueryAnswer {
        let friendIDs = mutualFriendIDs(for: person.id)
        let friendNames = friendIDs.compactMap { self.person(id: $0)?.name }
        return QueryAnswer(
            kind: .friends,
            title: "Freunde von \(person.name)",
            subtitle: friendNames.isEmpty
                ? "Noch keine gegenseitig bestätigte Freundschaft."
                : Self.germanList(friendNames),
            items: friendNames.map {
                QueryAnswerItem(
                    label: $0,
                    value: "Gegenseitig als Freund angegeben",
                    symbolName: "person.crop.circle.badge.checkmark"
                )
            },
            personIDs: [person.id] + friendIDs,
            groupIDs: data.groups
                .filter { $0.memberIDs.contains(person.id) }
                .map(\.id)
        )
    }

    private func groupsAnswer(for person: Person) -> QueryAnswer {
        let matchingGroups = data.groups.filter {
            $0.status.isVisible && $0.memberIDs.contains(person.id)
        }
        return QueryAnswer(
            kind: .groups,
            title: "Gruppen von \(person.name)",
            subtitle: matchingGroups.isEmpty
                ? "Noch keiner Gruppe zugeordnet."
                : "\(matchingGroups.count) Gruppe\(matchingGroups.count == 1 ? "" : "n")",
            items: matchingGroups.map { group in
                QueryAnswerItem(
                    label: group.name,
                    value: Self.germanList(
                        group.memberIDs.compactMap { self.person(id: $0)?.name }
                    ),
                    symbolName: "person.3.fill",
                    confidence: group.confidence
                )
            },
            personIDs: Array(Set(matchingGroups.flatMap(\.memberIDs))),
            groupIDs: matchingGroups.map(\.id)
        )
    }

    private func personalityAnswer(for person: Person) -> QueryAnswer {
        let facts = observations(for: person.id)
            .filter { $0.category == .personality }
        var items = person.temperamentTags.map {
            QueryAnswerItem(
                label: "Gemüt",
                value: $0,
                symbolName: "sparkles"
            )
        }
        items.append(
            contentsOf: facts.map {
                QueryAnswerItem(
                    label: $0.category.germanLabel,
                    value: $0.value,
                    symbolName: "quote.bubble",
                    confidence: $0.confidence
                )
            }
        )
        return QueryAnswer(
            kind: .personality,
            title: "So ist \(person.name)",
            subtitle: items.isEmpty ? "Noch keine Charakterbeschreibung eingetragen." : nil,
            items: items,
            personIDs: [person.id],
            mediaIDs: Array(Set(facts.flatMap(\.evidenceMediaIDs)))
        )
    }

    private func clothingAnswer(for person: Person) -> QueryAnswer {
        let personMedia = media(for: person.id)
        let clothingFacts = observations(for: person.id)
            .filter { $0.category == .clothing }
        let tagCounts = Dictionary(
            personMedia.flatMap(\.clothingTags).map { ($0, 1) },
            uniquingKeysWith: +
        )
        let commonTags = tagCounts
            .sorted {
                $0.value == $1.value
                    ? $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                    : $0.value > $1.value
            }

        var items = clothingFacts.map {
            QueryAnswerItem(
                label: "Beobachtung",
                value: $0.value,
                symbolName: "tshirt.fill",
                confidence: $0.confidence
            )
        }
        items.append(
            contentsOf: commonTags.prefix(6).map {
                QueryAnswerItem(
                    label: "Oft erkannt",
                    value: "\($0.key) · \($0.value)×",
                    symbolName: "camera.viewfinder"
                )
            }
        )

        return QueryAnswer(
            kind: .clothing,
            title: "Kleidungsstil von \(person.name)",
            subtitle: items.isEmpty
                ? "Noch keine Kleidung erfasst oder aus Medien abgeleitet."
                : nil,
            items: items,
            personIDs: [person.id],
            mediaIDs: Array(
                Set(
                    personMedia.map(\.id)
                        + clothingFacts.flatMap(\.evidenceMediaIDs)
                )
            )
        )
    }

    private func mediaAnswer(for person: Person) -> QueryAnswer {
        let items = media(for: person.id)
        let imageCount = items.filter { $0.kind == .image }.count
        let videoCount = items.filter { $0.kind == .video }.count
        return QueryAnswer(
            kind: .media,
            title: "Medien von \(person.name)",
            subtitle: items.isEmpty
                ? "Noch keine Fotos oder Videos importiert."
                : "\(imageCount) Foto\(imageCount == 1 ? "" : "s") · \(videoCount) Video\(videoCount == 1 ? "" : "s")",
            personIDs: [person.id],
            mediaIDs: items.map(\.id)
        )
    }

    private func linksAnswer(for person: Person) -> QueryAnswer {
        let links = person.links.filter(\.confirmed)
        return QueryAnswer(
            kind: .links,
            title: "Öffentliche Links von \(person.name)",
            subtitle: links.isEmpty
                ? "Noch keine bestätigte Webseite oder Social-Media-Adresse gespeichert."
                : "\(links.count) bestätigte\(links.count == 1 ? "r Link" : " Links")",
            items: links.map { link in
                QueryAnswerItem(
                    label: link.platform.germanLabel,
                    value: "\(link.displayTitle) · \(link.url)",
                    symbolName: link.platform.symbolName
                )
            },
            personIDs: [person.id]
        )
    }

    private static func normalized(_ value: String) -> String {
        let folded = value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "de_DE")
            )
            .lowercased()
        let scalars = folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func germanList(_ values: [String]) -> String {
        switch values.count {
        case 0: ""
        case 1: values[0]
        case 2: "\(values[0]) und \(values[1])"
        default:
            "\(values.dropLast().joined(separator: ", ")) und \(values.last ?? "")"
        }
    }

    // MARK: Optional demo seed

    public static func demoLibrary() -> LibraryData {
        let calendar = Calendar(identifier: .gregorian)
        let leni = Person(
            name: "Leni",
            birthday: calendar.date(from: DateComponents(year: 2002, month: 4, day: 18)),
            location: "Berlin",
            summary: "Leni hört aufmerksam zu und mag ruhige Abende.",
            temperamentTags: ["ruhig", "aufmerksam"],
            interests: ["Fotografie", "Musik"]
        )
        let nika = Person(
            name: "Nika",
            location: "Potsdam",
            summary: "Nika ist spontan und bringt Menschen zusammen.",
            temperamentTags: ["offen", "spontan"],
            interests: ["Tanzen", "Reisen"]
        )
        let mila = Person(
            name: "Mila",
            location: "Berlin",
            summary: "Mila ist kreativ und zuverlässig.",
            temperamentTags: ["kreativ", "zuverlässig"],
            interests: ["Design", "Kochen"]
        )
        let people = [leni, nika, mila]
        var claims: [RelationshipClaim] = []
        for source in people {
            for target in people where source.id != target.id {
                claims.append(
                    RelationshipClaim(
                        fromPersonID: source.id,
                        toPersonID: target.id,
                        status: .confirmed
                    )
                )
            }
        }
        let observations = [
            Observation(
                personID: leni.id,
                category: .clothing,
                value: "Trägt häufig neutrale Farben und schlichte Schnitte.",
                status: .likely,
                confidence: 0.78,
                source: .manual
            )
        ]
        return LibraryData(
            people: people,
            relationshipClaims: claims,
            observations: observations
        )
    }
}
