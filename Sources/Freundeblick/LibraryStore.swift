import AVFoundation
import Combine
import Darwin
import Foundation
import ImageIO

@_silgen_name("flock")
private func systemFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

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

public enum LibraryStoreError: LocalizedError, Equatable {
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
    case libraryUnavailable
    case backupNotFound
    case databaseChangedExternally
    case databaseLockUnavailable
    case invalidStoredMediaFilename(String)
    case invalidDatabaseStructure(String)
    case personChangedExternally
    case mediaChangedExternally
    case relationshipChangedExternally
    case groupChangedExternally
    case relationshipKindConflict

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
        case .libraryUnavailable:
            "Die Bibliothek ist zum Schutz deiner Daten schreibgeschützt, bis sie wieder erfolgreich geladen wurde."
        case .backupNotFound:
            "Es wurde keine wiederherstellbare Datenbanksicherung gefunden."
        case .databaseChangedExternally:
            "Die Datenbank wurde außerhalb der App geändert. Deine Änderung wurde nicht gespeichert. Lade die Bibliothek neu und versuche es danach noch einmal."
        case .databaseLockUnavailable:
            "Die Datenbank konnte nicht sicher für den Zugriff gesperrt werden."
        case let .invalidStoredMediaFilename(filename):
            "Der gespeicherte Medien-Dateiname „\(filename)“ ist unsicher oder ungültig."
        case let .invalidDatabaseStructure(reason):
            "Die Datenbank enthält widersprüchliche Daten: \(reason)"
        case .personChangedExternally:
            "Dieses Profil wurde inzwischen an anderer Stelle geändert. Deine ältere Fassung wurde nicht gespeichert. Schließe den Editor und öffne das Profil erneut."
        case .mediaChangedExternally:
            "Dieses Medium wurde inzwischen an anderer Stelle geändert. Deine ältere Fassung wurde nicht gespeichert. Öffne den Medieneditor erneut."
        case .relationshipChangedExternally:
            "Diese Verbindung wurde inzwischen an anderer Stelle geändert. Die ältere Änderung oder Löschung wurde nicht ausgeführt. Schließe den Editor und öffne die Verbindung erneut."
        case .groupChangedExternally:
            "Diese Gruppe wurde inzwischen an anderer Stelle geändert. Die ältere Änderung oder Löschung wurde nicht ausgeführt. Öffne die Gruppe erneut."
        case .relationshipKindConflict:
            "Zwischen diesen Personen besteht der gewählte Beziehungstyp bereits. Die vorhandene Verbindung wurde nicht überschrieben."
        }
    }
}

@MainActor
public final class LibraryStore: ObservableObject {
    private struct PendingMediaDeletion: Codable {
        let mediaID: UUID
        let storedFilename: String
        let deleteStoredFile: Bool

        init(
            mediaID: UUID,
            storedFilename: String,
            deleteStoredFile: Bool = true
        ) {
            self.mediaID = mediaID
            self.storedFilename = storedFilename
            self.deleteStoredFile = deleteStoredFile
        }

        private enum CodingKeys: String, CodingKey {
            case mediaID
            case storedFilename
            case deleteStoredFile
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mediaID = try container.decode(UUID.self, forKey: .mediaID)
            storedFilename = try container.decode(
                String.self,
                forKey: .storedFilename
            )
            deleteStoredFile = try container.decodeIfPresent(
                Bool.self,
                forKey: .deleteStoredFile
            ) ?? true
        }
    }

    private static let mediaDeletionJournalPrefix = ".delete-"
    private static let mediaDeletionJournalSuffix = ".json"

    @Published public private(set) var data: LibraryData
    @Published public private(set) var lastError: String?
    @Published public private(set) var isLibraryAvailable = true
    @Published public var presentNewPersonSheet = false

    public let databaseURL: URL
    public let mediaDirectory: URL
    private var lastPersistedSnapshot: Data?

    public var databaseBackupURL: URL {
        databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("friends.backup.json", isDirectory: false)
    }

    public var databasePreviousURL: URL {
        databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("friends.previous.json", isDirectory: false)
    }

    private var mediaDeletionJournalDirectory: URL {
        databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".MediaDeletionJournal",
                isDirectory: true
            )
    }

    public var hasDatabaseBackup: Bool {
        FileManager.default.fileExists(atPath: databaseBackupURL.path)
    }

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
                let loaded = try Self.withDatabaseLock(
                    databaseURL: self.databaseURL,
                    mode: LOCK_SH
                ) {
                    let loaded = try Self.loadValidatedLibrary(
                        at: self.databaseURL
                    )
                    try? loaded.encoded.write(
                        to: self.databaseBackupURL,
                        options: [.atomic]
                    )
                    return loaded
                }
                self.data = loaded.data
                self.lastPersistedSnapshot = loaded.encoded
            } else {
                self.data = seedDemoData ? Self.demoLibrary() : LibraryData()
                refreshInferredFriendshipGroups()
                try save()
            }
            try recoverPendingMediaDeletions()
            repairInvalidAvatarReferences()
            refreshInferredFriendshipGroups()
        } catch {
            self.isLibraryAvailable = false
            self.lastError = error.localizedDescription
        }
    }

    // MARK: Persistence

    public func reload() throws {
        do {
            let loaded = try Self.withDatabaseLock(
                databaseURL: databaseURL,
                mode: LOCK_SH
            ) {
                let loaded = try Self.loadValidatedLibrary(at: databaseURL)
                try? loaded.encoded.write(
                    to: databaseBackupURL,
                    options: [.atomic]
                )
                return loaded
            }
            data = loaded.data
            lastPersistedSnapshot = loaded.encoded
            try recoverPendingMediaDeletions()
            repairInvalidAvatarReferences()
            refreshInferredFriendshipGroups()
            isLibraryAvailable = true
            lastError = nil
        } catch {
            isLibraryAvailable = false
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Encodes the complete library and atomically replaces `friends.json`.
    public func save() throws {
        do {
            guard isLibraryAvailable else {
                throw LibraryStoreError.libraryUnavailable
            }
            try ensureRepositoryDirectories()
            let encoded = try encodedLibraryDataForPersistence()

            try Self.withDatabaseLock(
                databaseURL: databaseURL,
                mode: LOCK_EX
            ) {
                try persistEncodedLibraryDataAssumingDatabaseLock(
                    encoded,
                    expectedSnapshot: lastPersistedSnapshot
                )
            }
            lastPersistedSnapshot = encoded
            lastError = nil
        } catch {
            if error as? LibraryStoreError == .databaseChangedExternally {
                isLibraryAvailable = false
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    private func encodedLibraryDataForPersistence() throws -> Data {
        data.schemaVersion = LibraryData.currentSchemaVersion
        data.lastUpdated = Date()
        try Self.validateLoadedLibrary(data)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        return try encoder.encode(data)
    }

    private func persistEncodedLibraryDataAssumingDatabaseLock(
        _ encoded: Data,
        expectedSnapshot: Data?
    ) throws {
        let fileManager = FileManager.default
        let currentSnapshot = try currentDatabaseSnapshotAssumingLock()
        try requireExpectedDatabaseSnapshotAssumingLock(
            expectedSnapshot,
            currentSnapshot: currentSnapshot
        )

        let previousBackup = fileManager.fileExists(
            atPath: databaseBackupURL.path
        )
            ? try Data(contentsOf: databaseBackupURL)
            : nil

        if let currentSnapshot {
            try currentSnapshot.write(
                to: databasePreviousURL,
                options: [.atomic]
            )
        }
        try encoded.write(to: databaseBackupURL, options: [.atomic])
        do {
            try encoded.write(to: databaseURL, options: [.atomic])
        } catch {
            if let previousBackup {
                try? previousBackup.write(
                    to: databaseBackupURL,
                    options: [.atomic]
                )
            } else {
                try? fileManager.removeItem(at: databaseBackupURL)
            }
            throw error
        }
    }

    private func currentDatabaseSnapshotAssumingLock() throws -> Data? {
        FileManager.default.fileExists(atPath: databaseURL.path)
            ? try Data(contentsOf: databaseURL)
            : nil
    }

    private func requireExpectedDatabaseSnapshotAssumingLock(
        _ expectedSnapshot: Data?,
        currentSnapshot: Data? = nil
    ) throws {
        let current = try currentSnapshot
            ?? currentDatabaseSnapshotAssumingLock()
        switch (expectedSnapshot, current) {
        case (nil, nil):
            break
        case let (expected?, current?) where expected == current:
            break
        default:
            throw LibraryStoreError.databaseChangedExternally
        }
    }

    public func restoreDatabaseBackup() throws {
        do {
            guard hasDatabaseBackup else {
                throw LibraryStoreError.backupNotFound
            }
            try ensureRepositoryDirectories()
            let loaded = try Self.withDatabaseLock(
                databaseURL: databaseURL,
                mode: LOCK_EX
            ) {
                let loaded = try Self.loadValidatedLibrary(
                    at: databaseBackupURL
                )

                if FileManager.default.fileExists(atPath: databaseURL.path) {
                    let failedCopyURL = databaseURL
                        .deletingLastPathComponent()
                        .appendingPathComponent(
                            "friends.nicht-geladen-"
                                + "\(Self.recoveryTimestamp())-"
                                + "\(UUID().uuidString.lowercased()).json",
                            isDirectory: false
                        )
                    let currentBytes = try Data(contentsOf: databaseURL)
                    try currentBytes.write(to: failedCopyURL, options: [.atomic])
                }

                try loaded.encoded.write(to: databaseURL, options: [.atomic])
                return loaded
            }

            data = loaded.data
            lastPersistedSnapshot = loaded.encoded
            try recoverPendingMediaDeletions()
            repairInvalidAvatarReferences()
            refreshInferredFriendshipGroups()
            isLibraryAvailable = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private static func loadLibrary(at url: URL) throws -> (
        data: LibraryData,
        encoded: Data
    ) {
        let encoded = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try decoder.decode(LibraryData.self, from: encoded), encoded)
    }

    private static func loadValidatedLibrary(at url: URL) throws -> (
        data: LibraryData,
        encoded: Data
    ) {
        let loaded = try loadLibrary(at: url)
        guard loaded.data.schemaVersion <= LibraryData.currentSchemaVersion else {
            throw LibraryStoreError.invalidSchemaVersion(
                loaded.data.schemaVersion
            )
        }
        try validateLoadedLibrary(loaded.data)
        return loaded
    }

    private static func validateLoadedLibrary(_ library: LibraryData) throws {
        try requireUniqueIDs(library.people, collection: "Personen")
        try requireUniqueIDs(
            library.relationshipClaims,
            collection: "Beziehungen"
        )
        try requireUniqueIDs(library.media, collection: "Medien")
        try requireUniqueIDs(library.observations, collection: "Beobachtungen")
        try requireUniqueIDs(library.groups, collection: "Gruppen")

        let personIDs = Set(library.people.map(\.id))
        let mediaIDs = Set(library.media.map(\.id))

        for person in library.people {
            guard !person.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Eine Person hat keinen Namen."
                )
            }
        }

        var storedMediaFilenames = Set<String>()
        for item in library.media {
            try validateStoredMediaFilename(item.storedFilename)
            let normalizedFilename = item.storedFilename
                .precomposedStringWithCanonicalMapping
                .folding(
                    options: [.caseInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
            guard storedMediaFilenames.insert(normalizedFilename).inserted else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Mehrere Medien verwenden denselben gespeicherten Dateinamen."
                )
            }
            let unknownPeople = Set(item.personIDs).subtracting(personIDs)
            guard unknownPeople.isEmpty else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Ein Medium verweist auf eine unbekannte Person."
                )
            }
        }

        for claim in library.relationshipClaims {
            guard claim.fromPersonID != claim.toPersonID else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Eine Beziehung verweist zweimal auf dieselbe Person."
                )
            }
            guard personIDs.contains(claim.fromPersonID),
                  personIDs.contains(claim.toPersonID)
            else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Eine Beziehung verweist auf eine unbekannte Person."
                )
            }
        }

        for observation in library.observations {
            guard personIDs.contains(observation.personID) else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Eine Beobachtung verweist auf eine unbekannte Person."
                )
            }
            guard observation.confidence.isFinite,
                  (0 ... 1).contains(observation.confidence)
            else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Eine Beobachtung hat einen ungültigen Vertrauenswert."
                )
            }
            let unknownMedia = Set(observation.evidenceMediaIDs)
                .subtracting(mediaIDs)
            guard unknownMedia.isEmpty else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Eine Beobachtung verweist auf ein unbekanntes Medium."
                )
            }
        }

        for group in library.groups {
            guard group.confidence.isFinite,
                  (0 ... 1).contains(group.confidence)
            else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Eine Gruppe hat einen ungültigen Vertrauenswert."
                )
            }
            let unknownPeople = Set(group.memberIDs).subtracting(personIDs)
            guard unknownPeople.isEmpty else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Eine Gruppe verweist auf eine unbekannte Person."
                )
            }
        }
    }

    private static func requireUniqueIDs<Item: Identifiable>(
        _ items: [Item],
        collection: String
    ) throws where Item.ID == UUID {
        guard Set(items.map(\.id)).count == items.count else {
            throw LibraryStoreError.invalidDatabaseStructure(
                "\(collection) enthalten doppelte IDs."
            )
        }
    }

    private static func validateStoredMediaFilename(_ filename: String) throws {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              filename != ".",
              filename != "..",
              !filename.hasPrefix("/"),
              !filename.contains("/"),
              !filename.contains("\\"),
              !filename.contains("\0"),
              URL(fileURLWithPath: filename).lastPathComponent == filename
        else {
            throw LibraryStoreError.invalidStoredMediaFilename(filename)
        }
    }

    private static func recoveryTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func withDatabaseLock<Result>(
        databaseURL: URL,
        mode: Int32,
        _ operation: () throws -> Result
    ) throws -> Result {
        let lockURL = databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                databaseURL.lastPathComponent + ".lock",
                isDirectory: false
            )
        let descriptor = lockURL.path.withCString {
            Darwin.open(
                $0,
                O_CREAT | O_RDWR,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw LibraryStoreError.databaseLockUnavailable
        }
        defer {
            _ = Darwin.close(descriptor)
        }

        guard systemFlock(descriptor, mode) == 0 else {
            throw LibraryStoreError.databaseLockUnavailable
        }
        defer {
            _ = systemFlock(descriptor, LOCK_UN)
        }

        return try operation()
    }

    private func ensureRepositoryDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if (try? fileManager.destinationOfSymbolicLink(
            atPath: databaseURL.path
        )) != nil {
            throw LibraryStoreError.invalidDatabaseStructure(
                "friends.json darf keine symbolische Verknüpfung sein."
            )
        }
        try fileManager.createDirectory(
            at: mediaDirectory,
            withIntermediateDirectories: true
        )
        let mediaDirectoryValues = try mediaDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard mediaDirectoryValues.isDirectory == true,
              mediaDirectoryValues.isSymbolicLink != true
        else {
            throw LibraryStoreError.invalidDatabaseStructure(
                "Der Medienordner ist kein sicherer lokaler Ordner."
            )
        }

        try fileManager.createDirectory(
            at: mediaDeletionJournalDirectory,
            withIntermediateDirectories: true
        )
        let journalDirectoryValues = try mediaDeletionJournalDirectory
            .resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        guard journalDirectoryValues.isDirectory == true,
              journalDirectoryValues.isSymbolicLink != true
        else {
            throw LibraryStoreError.invalidDatabaseStructure(
                "Der interne Medien-Löschordner ist unsicher."
            )
        }
    }

    private func openSecureMediaDirectoryDescriptor() throws -> Int32 {
        let descriptor = mediaDirectory.path.withCString {
            Darwin.open(
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw Self.posixFileError(
                "Der Medienordner konnte nicht sicher geöffnet werden."
            )
        }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR
        else {
            let error = Self.posixFileError(
                "Der geöffnete Medienpfad ist kein sicherer Ordner."
            )
            _ = Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    private static func writePrivateMediaData(
        _ data: Data,
        temporaryFilename: String,
        destinationFilename: String,
        directoryDescriptor: Int32
    ) throws {
        try validateStoredMediaFilename(temporaryFilename)
        try validateStoredMediaFilename(destinationFilename)

        let descriptor = temporaryFilename.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw posixFileError(
                "Die private Profilbild-Datei konnte nicht erstellt werden."
            )
        }

        var shouldRemoveTemporaryFile = true
        defer {
            _ = Darwin.close(descriptor)
            if shouldRemoveTemporaryFile {
                temporaryFilename.withCString {
                    _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
        }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else {
                    throw posixFileError(
                        "Das Profilbild konnte nicht vollständig gespeichert werden."
                    )
                }
                offset += count
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw posixFileError(
                "Das Profilbild konnte nicht sicher abgeschlossen werden."
            )
        }

        let renameResult = temporaryFilename.withCString { temporaryName in
            destinationFilename.withCString { destinationName in
                Darwin.renameatx_np(
                    directoryDescriptor,
                    temporaryName,
                    directoryDescriptor,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0 else {
            throw posixFileError(
                "Das Profilbild konnte nicht sicher übernommen werden."
            )
        }
        shouldRemoveTemporaryFile = false
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            destinationFilename.withCString {
                _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
            }
            _ = Darwin.fsync(directoryDescriptor)
            throw posixFileError(
                "Der Medienordner konnte nicht sicher abgeschlossen werden."
            )
        }
    }

    private func secureStoredMediaFileExists(
        _ storedFilename: String,
        directoryDescriptor: Int32
    ) throws -> Bool {
        try Self.validateStoredMediaFilename(storedFilename)
        var information = stat()
        let result = storedFilename.withCString {
            Darwin.fstatat(
                directoryDescriptor,
                $0,
                &information,
                AT_SYMLINK_NOFOLLOW
            )
        }
        guard result == 0 else {
            if errno == ENOENT {
                return false
            }
            throw Self.posixFileError(
                "Die Mediendatei konnte nicht sicher geprüft werden."
            )
        }
        guard information.st_mode & S_IFMT == S_IFREG else {
            throw LibraryStoreError.invalidStoredMediaFilename(
                storedFilename
            )
        }
        return true
    }

    private func deleteStoredMediaFile(
        _ storedFilename: String,
        directoryDescriptor: Int32
    ) throws {
        guard try secureStoredMediaFileExists(
            storedFilename,
            directoryDescriptor: directoryDescriptor
        ) else {
            return
        }
        let result = storedFilename.withCString {
            Darwin.unlinkat(directoryDescriptor, $0, 0)
        }
        guard result == 0 else {
            throw Self.posixFileError(
                "Die lokale Medienkopie konnte nicht gelöscht werden."
            )
        }
    }

    private static func posixFileError(_ description: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: description]
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

    public func updatePerson(
        _ person: Person,
        expecting original: Person
    ) throws {
        guard self.person(id: person.id) == original else {
            throw LibraryStoreError.personChangedExternally
        }
        try updatePerson(person)
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
        replacingKind: RelationshipKind? = nil,
        expecting expectedClaims: [RelationshipClaim]? = nil
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
        if let expectedClaims {
            let currentClaims = matchingRelationshipClaims(
                between: fromPersonID,
                and: toPersonID,
                kinds: kindsToReplace
            )
            guard normalizedRelationshipClaims(currentClaims)
                == normalizedRelationshipClaims(expectedClaims)
            else {
                throw LibraryStoreError.relationshipChangedExternally
            }
        }

        if let replacingKind,
           replacingKind != kind {
            let targetKindAlreadyExists = data.relationshipClaims.contains { claim in
                let isSamePair =
                    (claim.fromPersonID == fromPersonID
                        && claim.toPersonID == toPersonID)
                    || (claim.fromPersonID == toPersonID
                        && claim.toPersonID == fromPersonID)
                return isSamePair && claim.kind == kind
            }
            guard !targetKindAlreadyExists else {
                throw LibraryStoreError.relationshipKindConflict
            }
        }

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
        kind: RelationshipKind,
        expecting expectedClaims: [RelationshipClaim]? = nil
    ) throws {
        let matchingClaims = matchingRelationshipClaims(
            between: firstPersonID,
            and: secondPersonID,
            kinds: [kind]
        )
        if let expectedClaims {
            guard normalizedRelationshipClaims(matchingClaims)
                == normalizedRelationshipClaims(expectedClaims)
            else {
                throw LibraryStoreError.relationshipChangedExternally
            }
        }
        guard !matchingClaims.isEmpty else {
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

    private func matchingRelationshipClaims(
        between firstPersonID: UUID,
        and secondPersonID: UUID,
        kinds: Set<RelationshipKind>
    ) -> [RelationshipClaim] {
        data.relationshipClaims.filter { claim in
            let isSamePair =
                (claim.fromPersonID == firstPersonID
                    && claim.toPersonID == secondPersonID)
                || (claim.fromPersonID == secondPersonID
                    && claim.toPersonID == firstPersonID)
            return isSamePair && kinds.contains(claim.kind)
        }
    }

    private func normalizedRelationshipClaims(
        _ claims: [RelationshipClaim]
    ) -> [RelationshipClaim] {
        claims.sorted { $0.id.uuidString < $1.id.uuidString }
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
        (try? validatedMediaURL(for: item))
            ?? mediaDirectory.appendingPathComponent(
                ".invalid-reference-\(item.id.uuidString)",
                isDirectory: false
            )
    }

    public func validatedMediaURL(for item: MediaItem) throws -> URL {
        try validatedMediaURL(storedFilename: item.storedFilename)
    }

    private func validatedMediaURL(storedFilename: String) throws -> URL {
        try Self.validateStoredMediaFilename(storedFilename)

        let base = mediaDirectory.standardizedFileURL
        let candidate = base
            .appendingPathComponent(storedFilename, isDirectory: false)
            .standardizedFileURL
        let resolvedBase = base.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard candidate != base,
              candidate.deletingLastPathComponent() == base,
              resolvedCandidate.deletingLastPathComponent() == resolvedBase
        else {
            throw LibraryStoreError.invalidStoredMediaFilename(
                storedFilename
            )
        }

        if FileManager.default.fileExists(atPath: candidate.path) {
            let values = try candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw LibraryStoreError.invalidStoredMediaFilename(
                    storedFilename
                )
            }
        }
        return candidate
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
        for personID: UUID,
        source: ProfileImageImportSource = .file,
        capturedAt: Date? = nil
    ) throws -> MediaItem {
        guard person(id: personID) != nil else {
            throw LibraryStoreError.personNotFound(personID)
        }
        guard let storedPNGData =
            Self.canonicalCroppedProfilePNG(pngData)
        else {
            throw LibraryStoreError.unsupportedMedia(
                URL(fileURLWithPath: originalFilename)
            )
        }
        try ensureRepositoryDirectories()

        let previous = data
        let storedFilename = "\(UUID().uuidString.lowercased())-profile.png"
        let temporaryFilename = ".crop-\(UUID().uuidString)"
        let cleanOriginalName = originalFilename
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayFilename = cleanOriginalName.isEmpty
            ? "Profilbild-Zuschnitt.png"
            : "\(URL(fileURLWithPath: cleanOriginalName).deletingPathExtension().lastPathComponent)-Profilbild.png"
        let tags: [String]
        let notes: String
        switch source {
        case .camera:
            tags = ["Profilbild-Zuschnitt", "Kameraaufnahme"]
            notes = "Direkt mit einer Kamera aufgenommen; gespeichert wurde nur der quadratische Profilbild-Zuschnitt."
        case .iPhoneImport:
            tags = ["Profilbild-Zuschnitt", "iPhone-Import"]
            notes = "Von einem verbundenen iPhone importiert; gespeichert wurde nur der quadratische Profilbild-Zuschnitt."
        case .file, .existingMedia:
            tags = ["Profilbild-Zuschnitt"]
            notes = "Quadratischer Profilbild-Zuschnitt; das ursprüngliche Bild wurde nicht verändert."
        }
        let item = MediaItem(
            storedFilename: storedFilename,
            originalFilename: displayFilename,
            kind: .image,
            personIDs: [personID],
            capturedAt: capturedAt,
            tags: tags,
            notes: notes
        )

        let mediaDirectoryDescriptor =
            try openSecureMediaDirectoryDescriptor()
        defer {
            _ = Darwin.close(mediaDirectoryDescriptor)
        }

        var installedDestination = false
        do {
            try Self.writePrivateMediaData(
                storedPNGData,
                temporaryFilename: temporaryFilename,
                destinationFilename: storedFilename,
                directoryDescriptor: mediaDirectoryDescriptor
            )
            installedDestination = true
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
            if installedDestination {
                try? deleteStoredMediaFile(
                    storedFilename,
                    directoryDescriptor: mediaDirectoryDescriptor
                )
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    public func addMedia(_ item: MediaItem) throws {
        try validatePersonReferences(item.personIDs)
        try Self.validateStoredMediaFilename(item.storedFilename)
        try transaction {
            if let index = data.media.firstIndex(where: { $0.id == item.id }) {
                data.media[index] = item
            } else {
                data.media.append(item)
            }
            clearAvatarReferencesInvalidated(by: item)
        }
    }

    public func updateMedia(_ item: MediaItem) throws {
        try validatePersonReferences(item.personIDs)
        try Self.validateStoredMediaFilename(item.storedFilename)
        guard data.media.contains(where: { $0.id == item.id }) else {
            throw LibraryStoreError.mediaNotFound(item.id)
        }
        try transaction {
            guard let index = data.media.firstIndex(where: { $0.id == item.id }) else {
                throw LibraryStoreError.mediaNotFound(item.id)
            }
            data.media[index] = item
            clearAvatarReferencesInvalidated(by: item)
        }
    }

    public func updateMedia(
        _ item: MediaItem,
        expecting original: MediaItem
    ) throws {
        guard mediaItem(id: item.id) == original else {
            throw LibraryStoreError.mediaChangedExternally
        }
        try updateMedia(item)
    }

    public func updateMediaAndRefreshPatterns(
        _ item: MediaItem,
        expecting original: MediaItem
    ) throws {
        try validatePersonReferences(item.personIDs)
        try Self.validateStoredMediaFilename(item.storedFilename)
        guard mediaItem(id: item.id) == original else {
            throw LibraryStoreError.mediaChangedExternally
        }
        let affectedPeople = Set(original.personIDs).union(item.personIDs)
        try transaction {
            guard let index = data.media.firstIndex(where: { $0.id == item.id })
            else {
                throw LibraryStoreError.mediaNotFound(item.id)
            }
            data.media[index] = item
            clearAvatarReferencesInvalidated(by: item)
            refreshConfirmedClothingPatternsInPlace(for: affectedPeople)
        }
    }

    private func clearAvatarReferencesInvalidated(by item: MediaItem) {
        guard item.kind != .image || !item.personIDs.isEmpty else {
            for index in data.people.indices
            where data.people[index].avatarMediaID == item.id {
                data.people[index].avatarMediaID = nil
            }
            return
        }

        for index in data.people.indices
        where data.people[index].avatarMediaID == item.id {
            if item.kind != .image
                || !item.personIDs.contains(data.people[index].id) {
                data.people[index].avatarMediaID = nil
            }
        }
    }

    private func repairInvalidAvatarReferences() {
        let mediaByID = Dictionary(
            data.media.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for index in data.people.indices {
            guard let avatarID = data.people[index].avatarMediaID else {
                continue
            }
            guard let avatar = mediaByID[avatarID],
                  avatar.kind == .image,
                  avatar.personIDs.contains(data.people[index].id)
            else {
                data.people[index].avatarMediaID = nil
                continue
            }
        }
    }

    public func deleteMedia(id: UUID, deleteStoredFile: Bool = false) throws {
        guard isLibraryAvailable else {
            throw LibraryStoreError.libraryUnavailable
        }
        guard let item = mediaItem(id: id) else {
            throw LibraryStoreError.mediaNotFound(id)
        }
        try ensureRepositoryDirectories()
        let mediaDirectoryDescriptor = try openSecureMediaDirectoryDescriptor()
        defer {
            _ = Darwin.close(mediaDirectoryDescriptor)
        }

        let previousData = data
        var cleanupNotice: String?
        do {
            try Self.withDatabaseLock(
                databaseURL: databaseURL,
                mode: LOCK_EX
            ) {
                try requireExpectedDatabaseSnapshotAssumingLock(
                    lastPersistedSnapshot
                )
                try neutralizePendingMediaDeletionJournals(for: id)

                var pendingDeletion: (
                    journalURL: URL,
                    record: PendingMediaDeletion
                )?
                if deleteStoredFile,
                   try secureStoredMediaFileExists(
                       item.storedFilename,
                       directoryDescriptor: mediaDirectoryDescriptor
                   ) {
                    let record = PendingMediaDeletion(
                        mediaID: item.id,
                        storedFilename: item.storedFilename
                    )
                    let journalURL = mediaDeletionJournalDirectory
                        .appendingPathComponent(
                            Self.mediaDeletionJournalPrefix
                                + "\(item.id.uuidString.lowercased())-"
                                + "\(UUID().uuidString.lowercased())"
                                + Self.mediaDeletionJournalSuffix,
                            isDirectory: false
                        )
                    try JSONEncoder().encode(record).write(
                        to: journalURL,
                        options: [.atomic]
                    )
                    pendingDeletion = (journalURL, record)
                }

                do {
                    data.media.removeAll { $0.id == id }
                    data.observations = data.observations.map { observation in
                        var updated = observation
                        updated.evidenceMediaIDs.removeAll { $0 == id }
                        return updated
                    }
                    for index in data.people.indices
                    where data.people[index].avatarMediaID == id {
                        data.people[index].avatarMediaID = nil
                    }
                    refreshConfirmedClothingPatternsInPlace(
                        for: Set(item.personIDs)
                    )

                    let deletionSnapshot =
                        try encodedLibraryDataForPersistence()
                    try persistEncodedLibraryDataAssumingDatabaseLock(
                        deletionSnapshot,
                        expectedSnapshot: lastPersistedSnapshot
                    )
                    lastPersistedSnapshot = deletionSnapshot
                } catch {
                    data = previousData
                    throw error
                }

                guard let pendingDeletion else {
                    return
                }

                do {
                    try deleteStoredMediaFile(
                        pendingDeletion.record.storedFilename,
                        directoryDescriptor: mediaDirectoryDescriptor
                    )
                } catch let fileDeletionError {
                    let deletionState = data
                    let deletionSnapshot = lastPersistedSnapshot
                    data = previousData
                    do {
                        let rollbackSnapshot =
                            try encodedLibraryDataForPersistence()
                        try persistEncodedLibraryDataAssumingDatabaseLock(
                            rollbackSnapshot,
                            expectedSnapshot: deletionSnapshot
                        )
                        lastPersistedSnapshot = rollbackSnapshot
                    } catch let rollbackError {
                        data = deletionState
                        throw rollbackError
                    }

                    try? neutralizePendingMediaDeletionJournals(for: id)
                    throw fileDeletionError
                }

                do {
                    try FileManager.default.removeItem(
                        at: pendingDeletion.journalURL
                    )
                } catch {
                    cleanupNotice = [
                        "Die lokale Kopie wurde gelöscht.",
                        "Ein internes Löschprotokoll konnte noch nicht entfernt werden",
                        "und wird beim nächsten Start bereinigt:",
                        error.localizedDescription,
                    ].joined(separator: " ")
                }
            }
            lastError = cleanupNotice
        } catch {
            if error as? LibraryStoreError == .databaseChangedExternally {
                isLibraryAvailable = false
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    public func deleteMedia(
        id: UUID,
        deleteStoredFile: Bool = false,
        expecting original: MediaItem
    ) throws {
        guard mediaItem(id: id) == original else {
            throw LibraryStoreError.mediaChangedExternally
        }
        try deleteMedia(id: id, deleteStoredFile: deleteStoredFile)
    }

    private func neutralizePendingMediaDeletionJournals(
        for mediaID: UUID
    ) throws {
        let fileManager = FileManager.default
        let filenamePrefix = Self.mediaDeletionJournalPrefix
            + mediaID.uuidString.lowercased()
            + "-"
        let entries = try fileManager.contentsOfDirectory(
            at: mediaDeletionJournalDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )

        for journalURL in entries
        where journalURL.lastPathComponent.lowercased()
            .hasPrefix(filenamePrefix)
            && journalURL.lastPathComponent
                .hasSuffix(Self.mediaDeletionJournalSuffix) {
            let values = try journalURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Ein internes Medien-Löschprotokoll ist unsicher."
                )
            }

            let record = try JSONDecoder().decode(
                PendingMediaDeletion.self,
                from: Data(contentsOf: journalURL)
            )
            guard record.mediaID == mediaID else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Ein internes Medien-Löschprotokoll passt nicht zu seiner Datei."
                )
            }

            let cancelled = PendingMediaDeletion(
                mediaID: record.mediaID,
                storedFilename: record.storedFilename,
                deleteStoredFile: false
            )
            try JSONEncoder().encode(cancelled).write(
                to: journalURL,
                options: [.atomic]
            )
            try fileManager.removeItem(at: journalURL)
        }
    }

    private func recoverPendingMediaDeletions() throws {
        try ensureRepositoryDirectories()
        let mediaDirectoryDescriptor = try openSecureMediaDirectoryDescriptor()
        defer {
            _ = Darwin.close(mediaDirectoryDescriptor)
        }

        let loaded = try Self.withDatabaseLock(
            databaseURL: databaseURL,
            mode: LOCK_EX
        ) {
            let latest = try Self.loadValidatedLibrary(at: databaseURL)
            try recoverPendingMediaDeletionsAssumingDatabaseLock(
                currentLibrary: latest.data,
                mediaDirectoryDescriptor: mediaDirectoryDescriptor
            )
            return latest
        }
        data = loaded.data
        lastPersistedSnapshot = loaded.encoded
    }

    private func recoverPendingMediaDeletionsAssumingDatabaseLock(
        currentLibrary: LibraryData,
        mediaDirectoryDescriptor: Int32
    ) throws {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: mediaDeletionJournalDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )

        for journalURL in entries {
            let filename = journalURL.lastPathComponent
            guard filename.hasPrefix(Self.mediaDeletionJournalPrefix),
                  filename.hasSuffix(Self.mediaDeletionJournalSuffix)
            else {
                continue
            }

            let values = try journalURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Ein internes Medien-Löschprotokoll ist unsicher."
                )
            }

            let encoded = try Data(contentsOf: journalURL)
            let record = try JSONDecoder().decode(
                PendingMediaDeletion.self,
                from: encoded
            )
            try Self.validateStoredMediaFilename(record.storedFilename)

            let expectedPrefix = Self.mediaDeletionJournalPrefix
                + record.mediaID.uuidString.lowercased()
                + "-"
            guard filename.lowercased().hasPrefix(expectedPrefix) else {
                throw LibraryStoreError.invalidDatabaseStructure(
                    "Ein internes Medien-Löschprotokoll passt nicht zu seiner Datei."
                )
            }

            guard record.deleteStoredFile else {
                try fileManager.removeItem(at: journalURL)
                continue
            }

            if let currentItem = currentLibrary.media.first(where: {
                $0.id == record.mediaID
            }) {
                guard currentItem.storedFilename == record.storedFilename else {
                    throw LibraryStoreError.invalidDatabaseStructure(
                        "Ein offener Medien-Löschvorgang verweist auf eine andere Datei."
                    )
                }
                try fileManager.removeItem(at: journalURL)
                continue
            }

            try deleteStoredMediaFile(
                record.storedFilename,
                directoryDescriptor: mediaDirectoryDescriptor
            )
            try fileManager.removeItem(at: journalURL)
        }
    }

    @discardableResult
    public func restoreMissingMediaFile(
        id: UUID,
        from sourceURL: URL,
        expecting original: MediaItem
    ) throws -> MediaItem {
        guard mediaItem(id: id) == original else {
            throw LibraryStoreError.mediaChangedExternally
        }
        try ensureRepositoryDirectories()

        let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceValues = try sourceURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard sourceValues.isRegularFile == true,
              sourceValues.isSymbolicLink != true,
              (sourceValues.fileSize ?? 0) > 0,
              try Self.mediaKind(for: sourceURL) == original.kind
        else {
            throw LibraryStoreError.unsupportedMedia(sourceURL)
        }

        let destination = try validatedMediaURL(for: original)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let temporary = mediaDirectory.appendingPathComponent(
            ".restore-\(UUID().uuidString)",
            isDirectory: false
        )

        do {
            try FileManager.default.copyItem(at: sourceURL, to: temporary)
            try Self.validateMediaContents(
                at: temporary,
                expectedKind: original.kind,
                reportedURL: sourceURL
            )
            try FileManager.default.moveItem(at: temporary, to: destination)

            var updated = original
            updated.originalFilename = sourceURL.lastPathComponent
            do {
                try updateMedia(updated, expecting: original)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            return updated
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Creates explainable style observations from user-confirmed media tags only.
    func refreshConfirmedClothingPatterns(for personIDs: [UUID]) throws {
        try transaction {
            refreshConfirmedClothingPatternsInPlace(for: Set(personIDs))
        }
    }

    private func refreshConfirmedClothingPatternsInPlace(
        for personIDs: Set<UUID>
    ) {
        let knownMediaIDs = Set(data.media.map(\.id))

        for personID in personIDs {
            let personMedia = data.media.filter {
                $0.personIDs.contains(personID)
            }
            var evidenceByTag: [String: [UUID]] = [:]
            for item in personMedia {
                for tag in Set(item.clothingTags) {
                    evidenceByTag[tag, default: []].append(item.id)
                }
            }

            var activeObservationIDs = Set<UUID>()
            for (tag, evidenceIDs) in evidenceByTag {
                let ratio = Double(evidenceIDs.count)
                    / Double(personMedia.count)
                guard evidenceIDs.count >= 3, ratio >= 0.5 else {
                    continue
                }

                let value = "Trägt häufig \(tag) – auf "
                    + "\(evidenceIDs.count) von \(personMedia.count) "
                    + "bestätigten Aufnahmen."
                if let index = data.observations.firstIndex(where: {
                    $0.personID == personID
                        && $0.category == .clothing
                        && $0.source == .mediaAnalysis
                        && $0.value.localizedCaseInsensitiveContains(tag)
                }) {
                    data.observations[index].value = value
                    data.observations[index].confidence = min(
                        0.96,
                        0.55 + ratio * 0.4
                    )
                    data.observations[index].evidenceMediaIDs = evidenceIDs
                    if data.observations[index].status == .archived {
                        data.observations[index].status = .likely
                    }
                    activeObservationIDs.insert(data.observations[index].id)
                } else {
                    let observation = Observation(
                        personID: personID,
                        category: .clothing,
                        value: value,
                        status: .likely,
                        confidence: min(0.96, 0.55 + ratio * 0.4),
                        source: .mediaAnalysis,
                        evidenceMediaIDs: evidenceIDs
                    )
                    data.observations.append(observation)
                    activeObservationIDs.insert(observation.id)
                }
            }

            for index in data.observations.indices
            where data.observations[index].personID == personID
                && data.observations[index].category == .clothing
                && data.observations[index].source == .mediaAnalysis
                && !activeObservationIDs.contains(data.observations[index].id)
                && data.observations[index].status != .archived {
                data.observations[index].status = .archived
                data.observations[index].evidenceMediaIDs.removeAll {
                    !knownMediaIDs.contains($0)
                }
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
        var stagedURLs: [URL] = []
        var imported: [MediaItem] = []

        do {
            for sourceURL in urls {
                let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if scopedAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                let resourceValues = try sourceURL.resourceValues(
                    forKeys: [
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                    ]
                )
                guard resourceValues.isRegularFile == true,
                      resourceValues.isSymbolicLink != true,
                      (resourceValues.fileSize ?? 0) > 0
                else {
                    throw LibraryStoreError.unsupportedMedia(sourceURL)
                }
                let kind = try Self.mediaKind(for: sourceURL)

                let fileExtension = sourceURL.pathExtension.lowercased()
                let storedFilename = UUID().uuidString.lowercased()
                    + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
                let destination = mediaDirectory
                    .appendingPathComponent(storedFilename, isDirectory: false)
                let temporary = mediaDirectory
                    .appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: false)
                stagedURLs.append(temporary)

                try FileManager.default.copyItem(at: sourceURL, to: temporary)
                try Self.validateMediaContents(
                    at: temporary,
                    expectedKind: kind,
                    reportedURL: sourceURL
                )
                try FileManager.default.moveItem(at: temporary, to: destination)
                copiedURLs.append(destination)

                imported.append(
                    MediaItem(
                        storedFilename: storedFilename,
                        originalFilename: sourceURL.lastPathComponent,
                        kind: kind,
                        personIDs: personIDs,
                        capturedAt: resourceValues.contentModificationDate
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
            for stagedURL in stagedURLs {
                try? FileManager.default.removeItem(at: stagedURL)
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

    private static func validateMediaContents(
        at url: URL,
        expectedKind: MediaKind,
        reportedURL: URL
    ) throws {
        switch expectedKind {
        case .image:
            guard let source = CGImageSourceCreateWithURL(
                url as CFURL,
                nil
            ),
                  CGImageSourceGetCount(source) > 0,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
            else {
                throw LibraryStoreError.unsupportedMedia(reportedURL)
            }
        case .video:
            let asset = AVURLAsset(url: url)
            guard asset.isPlayable,
                  !asset.tracks(withMediaType: .video).isEmpty
            else {
                throw LibraryStoreError.unsupportedMedia(reportedURL)
            }
        }
    }

    private static func canonicalCroppedProfilePNG(
        _ data: Data
    ) -> Data? {
        let pngSignature: [UInt8] = [
            0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        ]
        guard data.count >= pngSignature.count,
              data.count <= 20 * 1_024 * 1_024,
              Array(data.prefix(pngSignature.count)) == pngSignature,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  nil
              ),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let width = (
                  properties[kCGImagePropertyPixelWidth] as? NSNumber
              )?.intValue,
              let height = (
                  properties[kCGImagePropertyPixelHeight] as? NSNumber
              )?.intValue,
              width > 0,
              width == height,
              width <= 4_096,
              let image = CGImageSourceCreateImageAtIndex(
                  source,
                  0,
                  nil
              ),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: sRGB,
            bitmapInfo:
                CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard let normalizedImage = context.makeImage() else {
            return nil
        }

        let normalizedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            normalizedData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, normalizedImage, nil)
        guard CGImageDestinationFinalize(destination),
              normalizedData.length <= 20 * 1_024 * 1_024
        else {
            return nil
        }
        return normalizedData as Data
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

    public func updateGroup(
        _ group: Group,
        expecting original: Group
    ) throws {
        guard data.groups.first(where: { $0.id == group.id }) == original else {
            throw LibraryStoreError.groupChangedExternally
        }
        try updateGroup(group)
    }

    public func deleteGroup(id: UUID) throws {
        guard data.groups.contains(where: { $0.id == id }) else {
            throw LibraryStoreError.groupNotFound(id)
        }
        try transaction(reinferGroups: true) {
            data.groups.removeAll { $0.id == id }
        }
    }

    public func deleteGroup(
        id: UUID,
        expecting original: Group
    ) throws {
        guard id == original.id,
              data.groups.first(where: { $0.id == id }) == original
        else {
            throw LibraryStoreError.groupChangedExternally
        }
        try deleteGroup(id: id)
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

        let ignoredWords: Set<String> = [
            "am", "an", "auf", "bitte", "das", "der", "die", "ein", "eine",
            "einer", "finde", "fur", "hat", "haben", "im", "in", "ist",
            "lebt", "mit", "oder", "person", "personen", "spielt", "spielen",
            "such", "suche", "und", "von", "was", "welche", "welcher",
            "welches", "wer", "wie", "wo", "wohnt", "zeige", "zu",
        ]
        let meaningfulTokens = normalizedQuery
            .split(separator: " ")
            .map(String.init)
            .filter { !ignoredWords.contains($0) }
        let queryTokens = meaningfulTokens.isEmpty
            ? normalizedQuery.split(separator: " ").map(String.init)
            : meaningfulTokens

        let scored = data.people.compactMap { person -> (Person, Int)? in
            var values = person.allNames
            values.append(person.location ?? "")
            values.append(person.summary)
            values.append(contentsOf: person.temperamentTags)
            values.append(contentsOf: person.interests)
            values.append(contentsOf: person.profileDetails.values.flatMap { $0 })
            values.append(
                contentsOf: person.links.flatMap {
                    [$0.title, $0.handle, $0.url, $0.platform.germanLabel]
                }
            )
            values.append(
                contentsOf: data.observations
                    .filter {
                        $0.personID == person.id
                            && $0.status == .confirmed
                    }
                    .flatMap { [$0.category.germanLabel, $0.value] }
            )

            let normalizedValues = values.map(Self.normalized)
            let words = normalizedValues.flatMap {
                $0.split(separator: " ").map(String.init)
            }
            let matchedTokens = queryTokens.filter { token in
                normalizedValues.contains { $0.contains(token) }
                    || words.contains {
                        Self.searchWordsMatch(query: token, candidate: $0)
                    }
            }
            guard matchedTokens.count == queryTokens.count else { return nil }

            var score = matchedTokens.count * 10
            if normalizedValues.contains(where: { $0.contains(normalizedQuery) }) {
                score += 8
            }
            if person.allNames.contains(where: {
                Self.normalized($0).contains(normalizedQuery)
            }) {
                score += 12
            }
            return (person, score)
        }

        return scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name)
                    == .orderedAscending
            }
            .map(\.0)
    }

    private static func searchWordsMatch(
        query: String,
        candidate: String
    ) -> Bool {
        guard !query.isEmpty, !candidate.isEmpty else { return false }
        if candidate.hasPrefix(query) || query.hasPrefix(candidate) {
            return min(query.count, candidate.count) >= 3
        }
        guard min(query.count, candidate.count) >= 5,
              abs(query.count - candidate.count) <= 1
        else {
            return false
        }
        return editDistance(query, candidate) <= 1
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let lhs = Array(left)
        let rhs = Array(right)
        var previous = Array(0 ... rhs.count)

        for (leftIndex, leftCharacter) in lhs.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(rhs.count + 1)
            for (rightIndex, rightCharacter) in rhs.enumerated() {
                current.append(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex]
                            + (leftCharacter == rightCharacter ? 0 : 1)
                    )
                )
            }
            previous = current
        }
        return previous.last ?? 0
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
