import AppKit
import Foundation
import ImageIO
import SwiftUI
import XCTest
@testable import Freundeblick

final class FreundeblickTests: XCTestCase {
    func testComparisonOverlapUsesNormalizedValuesAndTreatsMissingAsUnknown() {
        XCTAssertEqual(
            ComparisonEngine.overlapPercentage(
                ["Musik", "Grün"],
                ["musik", "grun", "Reisen"]
            ),
            200.0 / 3.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ComparisonEngine.overlapPercentage([], []),
            0
        )
        XCTAssertEqual(
            ComparisonEngine.sharedValues([
                ["Musik", "Reisen"],
                ["musik", "Kochen"],
                ["MUSIK"],
            ]),
            ["Musik"]
        )

        XCTAssertEqual(
            ComparisonEngine.averageKnownOverlap([
                (["Musik"], ["musik"]),
                (["ruhig"], ["offen"]),
                ([], ["unbekannt"]),
            ]) ?? -1,
            50,
            accuracy: 0.001
        )
        XCTAssertNil(
            ComparisonEngine.averageKnownOverlap([
                ([], []),
                (["Musik"], []),
            ])
        )
        let comparableColors = ComparisonEngine.comparableProfileValues([
            "favoriteColors": ["Blau"],
            "genderIdentity": ["nichtbinär"],
            "sexualOrientation": ["bisexuell"],
        ])
        XCTAssertEqual(comparableColors.count, 1)
        XCTAssertEqual(
            comparableColors.map(
                ComparisonEngine.displayComparableProfileValue
            ),
            ["Lieblingsfarbe: Blau"]
        )
        XCTAssertEqual(
            ComparisonEngine.overlapPercentage(
                ComparisonEngine.comparableProfileValues([
                    "favoriteColors": ["Blau"],
                ]),
                ComparisonEngine.comparableProfileValues([
                    "favoriteCars": ["Blau"],
                ])
            ),
            0
        )
        XCTAssertEqual(
            ComparisonEngine.overlapPercentage(
                ComparisonEngine.comparableProfileValues([
                    "favoriteColors": ["Blau"],
                ]),
                ComparisonEngine.comparableProfileValues([
                    "favoriteColors": ["blau"],
                ])
            ),
            100
        )
    }

    func testProfileSuggestionsCompleteShortPrefixesAndExcludeSelections() {
        XCTAssertEqual(
            ProfileSuggestionCatalog.matches(
                "ru",
                in: ProfileSuggestionCatalog.temperament
            ).first,
            "ruhig"
        )
        XCTAssertEqual(
            ProfileSuggestionCatalog.matches(
                "mu",
                in: ProfileSuggestionCatalog.interests
            ).first,
            "Musik"
        )
        XCTAssertFalse(
            ProfileSuggestionCatalog.matches(
                "",
                in: ["ruhig", "Ruhig", "offen"],
                excluding: ["ruhig"]
            ).contains { $0.localizedCaseInsensitiveCompare("ruhig") == .orderedSame }
        )
        XCTAssertEqual(
            ProfileSuggestionCatalog.matches(
                "ni",
                in: ProfileSuggestionCatalog.genderIdentities
            ).first,
            "nichtbinär"
        )
        XCTAssertEqual(
            ProfileSuggestionCatalog.matches(
                "bi",
                in: ProfileSuggestionCatalog.sexualOrientations
            ).first,
            "bisexuell"
        )
    }

    func testPeopleSelectionFollowsNewPeopleAndRepairsStaleIDs() {
        let leni = UUID()
        let nika = UUID()
        let removed = UUID()

        XCTAssertEqual(
            PeopleSelection.reconciled(
                current: nil,
                previousIDs: [],
                availableIDs: [leni]
            ),
            leni
        )
        XCTAssertEqual(
            PeopleSelection.reconciled(
                current: leni,
                previousIDs: [leni],
                availableIDs: [leni, nika]
            ),
            nika
        )
        XCTAssertEqual(
            PeopleSelection.reconciled(
                current: removed,
                previousIDs: [removed, leni],
                availableIDs: [leni]
            ),
            leni
        )
        XCTAssertNil(
            PeopleSelection.reconciled(
                current: leni,
                previousIDs: [leni],
                availableIDs: []
            )
        )
    }

    func testPeopleSelectionPreservesVisiblePersonWhileFiltering() {
        let leni = UUID()
        let nika = UUID()

        XCTAssertEqual(
            PeopleSelection.reconciled(
                current: nika,
                previousIDs: [leni, nika],
                availableIDs: [leni, nika],
                preferNew: false
            ),
            nika
        )
        XCTAssertEqual(
            PeopleSelection.reconciled(
                current: nika,
                previousIDs: [leni],
                availableIDs: [leni],
                preferNew: false
            ),
            leni
        )
    }

    func testAgeUsesBirthdayInsteadOfStoredNumber() {
        let calendar = Calendar(identifier: .gregorian)
        let person = Person(
            name: "Test",
            birthday: calendar.date(from: DateComponents(year: 2000, month: 8, day: 10))
        )
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 26))!

        XCTAssertEqual(person.age(on: referenceDate, calendar: calendar), 25)
    }

    func testFutureBirthdayDoesNotProduceNegativeAge() {
        let person = Person(
            name: "Test",
            birthday: Date().addingTimeInterval(86_400)
        )
        XCTAssertNil(person.age())
    }

    @MainActor
    func testNaturalSearchCombinesLocationInterestsAndToleratesOneTypo() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("Media")
        )
        let elias = Person(
            name: "Elias",
            location: "Schneverdingen",
            temperamentTags: ["ruhig"],
            interests: ["Badminton"]
        )
        let noah = Person(
            name: "Noah",
            location: "Hamburg",
            interests: ["Badminton"]
        )
        try store.addPerson(elias)
        try store.addPerson(noah)

        XCTAssertEqual(
            store.searchPeople(
                matching: "Wer spielt Badminten in Schneverdingen?"
            ).map(\.id),
            [elias.id]
        )
        XCTAssertEqual(
            store.searchPeople(matching: "wer ist ruhig").map(\.id),
            [elias.id]
        )
    }

    func testLegacyPersonWithoutLinksStillDecodes() throws {
        let data = Data(#"{"name":"Leni"}"#.utf8)
        let person = try JSONDecoder().decode(Person.self, from: data)

        XCTAssertEqual(person.name, "Leni")
        XCTAssertTrue(person.links.isEmpty)
        XCTAssertTrue(person.profileDetails.isEmpty)
    }

    @MainActor
    func testUnreadableDatabaseLocksWritesAndPreservesOriginalBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("friends.json")
        let invalidBytes = Data("{kaputt".utf8)
        try invalidBytes.write(to: databaseURL)

        let store = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )

        XCTAssertFalse(store.isLibraryAvailable)
        XCTAssertNotNil(store.lastError)
        XCTAssertThrowsError(try store.addPerson(Person(name: "Nicht speichern"))) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .libraryUnavailable
            )
        }
        XCTAssertEqual(try Data(contentsOf: databaseURL), invalidBytes)
    }

    @MainActor
    func testDatabaseBackupCanRestoreLastKnownGoodLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("friends.json")
        let store = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )
        try store.addPerson(Person(name: "Leni"))
        try store.addPerson(Person(name: "Noah"))
        XCTAssertTrue(store.hasDatabaseBackup)

        try Data("{unlesbar".utf8).write(to: databaseURL, options: [.atomic])
        XCTAssertThrowsError(try store.reload())
        XCTAssertFalse(store.isLibraryAvailable)

        try store.restoreDatabaseBackup()

        XCTAssertTrue(store.isLibraryAvailable)
        XCTAssertEqual(store.people.map(\.name), ["Leni", "Noah"])
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .contains { $0.hasPrefix("friends.nicht-geladen-") }
        )

        let reloaded = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )
        XCTAssertEqual(reloaded.people.map(\.name), ["Leni", "Noah"])
    }

    @MainActor
    func testRapidBackupRestoresKeepDistinctRecoveryCopies() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("friends.json")
        let initialStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )
        try initialStore.addPerson(Person(name: "Leni"))

        let corruptBytes = Data("{kaputt".utf8)
        try corruptBytes.write(to: databaseURL, options: [.atomic])
        let firstRecoveryStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )
        let secondRecoveryStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )

        try firstRecoveryStore.restoreDatabaseBackup()
        try secondRecoveryStore.restoreDatabaseBackup()

        let recoveryURLs = try FileManager.default
            .contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix(
                    "friends.nicht-geladen-"
                )
            }
        XCTAssertEqual(recoveryURLs.count, 2)
        XCTAssertTrue(
            try recoveryURLs.contains {
                try Data(contentsOf: $0) == corruptBytes
            }
        )
    }

    @MainActor
    func testConcurrentStoreDoesNotOverwriteNewerDatabaseState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("friends.json")
        let mediaURL = root.appendingPathComponent("Media")
        let firstStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaURL
        )
        try firstStore.addPerson(Person(name: "Leni"))

        let externalStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaURL
        )
        try externalStore.addPerson(Person(name: "Noah"))

        XCTAssertThrowsError(
            try firstStore.addPerson(Person(name: "Mia"))
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .databaseChangedExternally
            )
        }
        XCTAssertFalse(firstStore.isLibraryAvailable)

        let verificationStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaURL
        )
        XCTAssertEqual(
            Set(verificationStore.people.map(\.name)),
            Set(["Leni", "Noah"])
        )
    }

    @MainActor
    func testDuplicatePersistedIDsLockLibraryInsteadOfCrashing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let duplicateID = UUID()
        let invalidLibrary = LibraryData(
            media: [
                MediaItem(
                    id: duplicateID,
                    storedFilename: "eins.jpg",
                    originalFilename: "eins.jpg",
                    kind: .image
                ),
                MediaItem(
                    id: duplicateID,
                    storedFilename: "zwei.jpg",
                    originalFilename: "zwei.jpg",
                    kind: .image
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let databaseURL = root.appendingPathComponent("friends.json")
        try encoder.encode(invalidLibrary).write(to: databaseURL)

        let store = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )

        XCTAssertFalse(store.isLibraryAvailable)
        XCTAssertTrue(store.lastError?.contains("doppelte IDs") == true)
    }

    @MainActor
    func testDuplicateStoredMediaFilenameLocksLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let invalidLibrary = LibraryData(
            media: [
                MediaItem(
                    storedFilename: "bild.jpg",
                    originalFilename: "Erstes Bild.jpg",
                    kind: .image
                ),
                MediaItem(
                    storedFilename: "BILD.JPG",
                    originalFilename: "Zweites Bild.jpg",
                    kind: .image
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let databaseURL = root.appendingPathComponent("friends.json")
        try encoder.encode(invalidLibrary).write(to: databaseURL)

        let store = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )

        XCTAssertFalse(store.isLibraryAvailable)
        XCTAssertTrue(
            store.lastError?.contains("Dateinamen") == true
        )
    }

    @MainActor
    func testMediaImportRejectsFakeImageContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("Media")
        )
        let fakeImage = root.appendingPathComponent("kein-bild.jpg")
        try Data("Das ist kein Bild.".utf8).write(to: fakeImage)

        XCTAssertThrowsError(
            try store.importMedia(from: [fakeImage])
        )
        XCTAssertTrue(store.mediaItems.isEmpty)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: store.mediaDirectory,
                includingPropertiesForKeys: nil
            ).filter { !$0.lastPathComponent.hasPrefix(".") },
            []
        )
    }

    @MainActor
    func testMediaDeletionRejectsSymlinkAndKeepsTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaDirectory = root.appendingPathComponent("Media")
        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: mediaDirectory
        )
        let target = root.appendingPathComponent("nicht-loeschen.txt")
        try Data("wichtig".utf8).write(to: target)
        let link = mediaDirectory.appendingPathComponent("verknuepfung.jpg")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )
        let item = MediaItem(
            storedFilename: link.lastPathComponent,
            originalFilename: "verknuepfung.jpg",
            kind: .image
        )
        try store.addMedia(item)

        XCTAssertThrowsError(
            try store.deleteMedia(id: item.id, deleteStoredFile: true)
        )
        XCTAssertNotNil(store.mediaItem(id: item.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaDirectory.path))
    }

    @MainActor
    func testMediaDeletionRemovesFileAvatarEvidenceAndPersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("friends.json")
        let mediaDirectory = root.appendingPathComponent("Media")
        let store = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaDirectory
        )
        let person = Person(name: "Nika")
        try store.addPerson(person)

        let item = MediaItem(
            storedFilename: "erinnerung.png",
            originalFilename: "Erinnerung.png",
            kind: .image,
            personIDs: [person.id],
            tags: ["Urlaub"]
        )
        try validPNGData().write(
            to: mediaDirectory.appendingPathComponent(item.storedFilename)
        )
        try store.addMedia(item)
        try store.setAvatarMediaID(item.id, for: person.id)

        let observation = Observation(
            personID: person.id,
            category: .other,
            value: "Gemeinsamer Ausflug",
            status: .confirmed,
            evidenceMediaIDs: [item.id]
        )
        try store.addObservation(observation)

        try store.deleteMedia(id: item.id, deleteStoredFile: true)

        XCTAssertNil(store.mediaItem(id: item.id))
        XCTAssertNil(store.person(id: person.id)?.avatarMediaID)
        XCTAssertEqual(
            store.data.observations.first { $0.id == observation.id }?
                .evidenceMediaIDs,
            []
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: mediaDirectory
                    .appendingPathComponent(item.storedFilename)
                    .path
            )
        )

        let reloaded = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaDirectory
        )
        XCTAssertNil(reloaded.mediaItem(id: item.id))
        XCTAssertNil(reloaded.person(id: person.id)?.avatarMediaID)
        XCTAssertEqual(
            reloaded.data.observations.first { $0.id == observation.id }?
                .evidenceMediaIDs,
            []
        )
    }

    @MainActor
    func testMetadataOnlyMediaDeletionKeepsLocalCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaDirectory = root.appendingPathComponent("Media")
        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: mediaDirectory
        )
        let item = MediaItem(
            storedFilename: "behalten.png",
            originalFilename: "Behalten.png",
            kind: .image
        )
        let fileURL = mediaDirectory.appendingPathComponent(item.storedFilename)
        try validPNGData().write(to: fileURL)
        try store.addMedia(item)

        try store.deleteMedia(id: item.id, deleteStoredFile: false)

        XCTAssertNil(store.mediaItem(id: item.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @MainActor
    func testPendingMediaDeletionJournalRecoversBothCrashSides() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let committedRoot = root.appendingPathComponent(
            "committed",
            isDirectory: true
        )
        let committedMedia = committedRoot.appendingPathComponent(
            "Media",
            isDirectory: true
        )
        let committedDatabase = committedRoot.appendingPathComponent(
            "friends.json"
        )
        _ = LibraryStore(
            databaseURL: committedDatabase,
            mediaDirectory: committedMedia
        )
        let committedID = UUID()
        let committedFilename = "nach-commit.png"
        let committedFile = committedMedia.appendingPathComponent(
            committedFilename
        )
        try validPNGData().write(to: committedFile)
        let committedJournal = committedRoot
            .appendingPathComponent(".MediaDeletionJournal", isDirectory: true)
            .appendingPathComponent(
                ".delete-\(committedID.uuidString.lowercased())-test.json"
            )
        try pendingMediaDeletionJournal(
            mediaID: committedID,
            storedFilename: committedFilename
        ).write(to: committedJournal, options: [.atomic])

        _ = LibraryStore(
            databaseURL: committedDatabase,
            mediaDirectory: committedMedia
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: committedFile.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: committedJournal.path)
        )

        let rollbackRoot = root.appendingPathComponent(
            "rollback",
            isDirectory: true
        )
        let rollbackMedia = rollbackRoot.appendingPathComponent(
            "Media",
            isDirectory: true
        )
        let rollbackDatabase = rollbackRoot.appendingPathComponent(
            "friends.json"
        )
        let rollbackStore = LibraryStore(
            databaseURL: rollbackDatabase,
            mediaDirectory: rollbackMedia
        )
        let rollbackItem = MediaItem(
            storedFilename: "vor-commit.png",
            originalFilename: "Vor Commit.png",
            kind: .image
        )
        try rollbackStore.addMedia(rollbackItem)
        let rollbackFile = rollbackMedia.appendingPathComponent(
            rollbackItem.storedFilename
        )
        try validPNGData().write(to: rollbackFile)
        let rollbackJournal = rollbackRoot
            .appendingPathComponent(".MediaDeletionJournal", isDirectory: true)
            .appendingPathComponent(
                ".delete-\(rollbackItem.id.uuidString.lowercased())-test.json"
            )
        try pendingMediaDeletionJournal(
            mediaID: rollbackItem.id,
            storedFilename: rollbackItem.storedFilename
        ).write(to: rollbackJournal, options: [.atomic])

        let recoveredStore = LibraryStore(
            databaseURL: rollbackDatabase,
            mediaDirectory: rollbackMedia
        )
        XCTAssertNotNil(recoveredStore.mediaItem(id: rollbackItem.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollbackFile.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: rollbackJournal.path)
        )
    }

    @MainActor
    func testMetadataOnlyRetryNeutralizesOlderPhysicalDeletionJournal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("friends.json")
        let mediaDirectory = root.appendingPathComponent("Media")
        let store = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaDirectory
        )
        let item = MediaItem(
            storedFilename: "behalten-nach-fehler.png",
            originalFilename: "Behalten nach Fehler.png",
            kind: .image
        )
        try store.addMedia(item)
        let fileURL = mediaDirectory.appendingPathComponent(
            item.storedFilename
        )
        try validPNGData().write(to: fileURL)

        let journalURL = root
            .appendingPathComponent(".MediaDeletionJournal", isDirectory: true)
            .appendingPathComponent(
                ".delete-\(item.id.uuidString.lowercased())-alter-versuch.json"
            )
        try pendingMediaDeletionJournal(
            mediaID: item.id,
            storedFilename: item.storedFilename
        ).write(to: journalURL, options: [.atomic])

        try store.deleteMedia(id: item.id, deleteStoredFile: false)

        XCTAssertNil(store.mediaItem(id: item.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))

        let reloaded = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaDirectory
        )
        XCTAssertNil(reloaded.mediaItem(id: item.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @MainActor
    func testStaleStoreCannotCancelCommittedPhysicalDeletionJournal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("friends.json")
        let mediaDirectory = root.appendingPathComponent("Media")
        let committingStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaDirectory
        )
        let item = MediaItem(
            storedFilename: "gleichzeitig-loeschen.png",
            originalFilename: "Gleichzeitig löschen.png",
            kind: .image
        )
        try committingStore.addMedia(item)
        let fileURL = mediaDirectory.appendingPathComponent(
            item.storedFilename
        )
        try validPNGData().write(to: fileURL)

        let staleStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaDirectory
        )
        try committingStore.deleteMedia(
            id: item.id,
            deleteStoredFile: false
        )

        let journalURL = root
            .appendingPathComponent(".MediaDeletionJournal", isDirectory: true)
            .appendingPathComponent(
                ".delete-\(item.id.uuidString.lowercased())-crash.json"
            )
        try pendingMediaDeletionJournal(
            mediaID: item.id,
            storedFilename: item.storedFilename
        ).write(to: journalURL, options: [.atomic])

        XCTAssertThrowsError(
            try staleStore.deleteMedia(
                id: item.id,
                deleteStoredFile: false
            )
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .databaseChangedExternally
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let recoveredStore = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: mediaDirectory
        )
        XCTAssertNil(recoveredStore.mediaItem(id: item.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @MainActor
    func testMediaDeletionRejectsReplacedMediaDirectorySymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaDirectory = root.appendingPathComponent("Media")
        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: mediaDirectory
        )
        let item = MediaItem(
            storedFilename: "nicht-extern-loeschen.png",
            originalFilename: "Nicht extern löschen.png",
            kind: .image
        )
        try store.addMedia(item)
        try validPNGData().write(
            to: mediaDirectory.appendingPathComponent(item.storedFilename)
        )

        let originalMediaDirectory = root.appendingPathComponent(
            "OriginalMedia",
            isDirectory: true
        )
        try FileManager.default.moveItem(
            at: mediaDirectory,
            to: originalMediaDirectory
        )
        let externalDirectory = root.appendingPathComponent(
            "Extern",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: externalDirectory,
            withIntermediateDirectories: true
        )
        let externalFile = externalDirectory.appendingPathComponent(
            item.storedFilename
        )
        try validPNGData().write(to: externalFile)
        try FileManager.default.createSymbolicLink(
            at: mediaDirectory,
            withDestinationURL: externalDirectory
        )

        XCTAssertThrowsError(
            try store.deleteMedia(id: item.id, deleteStoredFile: true)
        )
        XCTAssertNotNil(store.mediaItem(id: item.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalFile.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: originalMediaDirectory
                    .appendingPathComponent(item.storedFilename)
                    .path
            )
        )
    }

    @MainActor
    func testMissingMediaFileCanBeRestoredWithoutLosingMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("Media")
        )
        let item = MediaItem(
            storedFilename: "gespeichert.jpg",
            originalFilename: "Verloren.jpg",
            kind: .image,
            tags: ["Urlaub"],
            notes: "Wichtig"
        )
        try store.addMedia(item)
        let replacement = root.appendingPathComponent("Wiedergefunden.jpg")
        let replacementBytes = try validPNGData()
        try replacementBytes.write(to: replacement)

        let restored = try store.restoreMissingMediaFile(
            id: item.id,
            from: replacement,
            expecting: item
        )

        XCTAssertEqual(restored.originalFilename, "Wiedergefunden.jpg")
        XCTAssertEqual(restored.tags, ["Urlaub"])
        XCTAssertEqual(restored.notes, "Wichtig")
        XCTAssertEqual(
            try Data(contentsOf: store.mediaURL(for: restored)),
            replacementBytes
        )
    }

    @MainActor
    func testDatabaseLeafSymlinkLocksLibraryWithoutChangingTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let targetURL = root.appendingPathComponent("actual.json")
        let targetStore = LibraryStore(
            databaseURL: targetURL,
            mediaDirectory: root.appendingPathComponent("TargetMedia")
        )
        try targetStore.addPerson(Person(name: "Leni"))
        let expectedBytes = try Data(contentsOf: targetURL)

        let linkedURL = root.appendingPathComponent("friends.json")
        try FileManager.default.createSymbolicLink(
            at: linkedURL,
            withDestinationURL: targetURL
        )
        let linkedStore = LibraryStore(
            databaseURL: linkedURL,
            mediaDirectory: root.appendingPathComponent("LinkedMedia")
        )

        XCTAssertFalse(linkedStore.isLibraryAvailable)
        XCTAssertTrue(
            linkedStore.lastError?.contains(
                "symbolische Verknüpfung"
            ) == true
        )
        XCTAssertEqual(try Data(contentsOf: targetURL), expectedBytes)
    }

    @MainActor
    func testDanglingDatabaseSymlinkIsNotReplacedByEmptyLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let missingTarget = root.appendingPathComponent("offline.json")
        let linkedURL = root.appendingPathComponent("friends.json")
        try FileManager.default.createSymbolicLink(
            at: linkedURL,
            withDestinationURL: missingTarget
        )

        let store = LibraryStore(
            databaseURL: linkedURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )

        XCTAssertFalse(store.isLibraryAvailable)
        XCTAssertTrue(
            store.lastError?.contains(
                "symbolische Verknüpfung"
            ) == true
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: missingTarget.path)
        )
        XCTAssertNotNil(
            try? FileManager.default.destinationOfSymbolicLink(
                atPath: linkedURL.path
            )
        )
    }

    @MainActor
    func testUnsafePersistedMediaFilenameLocksLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let invalidLibrary = LibraryData(
            media: [
                MediaItem(
                    storedFilename: "/",
                    originalFilename: "Media",
                    kind: .image
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let databaseURL = root.appendingPathComponent("friends.json")
        try encoder.encode(invalidLibrary).write(to: databaseURL)

        let store = LibraryStore(
            databaseURL: databaseURL,
            mediaDirectory: root.appendingPathComponent("Media")
        )

        XCTAssertFalse(store.isLibraryAvailable)
        XCTAssertTrue(store.lastError?.contains("unsicher") == true)
    }

    @MainActor
    func testStalePersonAndMediaDraftsCannotOverwriteNewerValues() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("Media")
        )
        let originalPerson = Person(name: "Leni", summary: "Alt")
        try store.addPerson(originalPerson)
        var newerPerson = originalPerson
        newerPerson.summary = "Neu von Codex"
        try store.updatePerson(newerPerson)
        var stalePersonDraft = originalPerson
        stalePersonDraft.summary = "Alter Editor"

        XCTAssertThrowsError(
            try store.updatePerson(
                stalePersonDraft,
                expecting: originalPerson
            )
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .personChangedExternally
            )
        }
        XCTAssertEqual(
            store.person(id: originalPerson.id)?.summary,
            "Neu von Codex"
        )

        let originalMedia = MediaItem(
            storedFilename: "leni.jpg",
            originalFilename: "Leni.jpg",
            kind: .image,
            tags: ["Alt"]
        )
        try store.addMedia(originalMedia)
        var newerMedia = originalMedia
        newerMedia.analysisLabels = ["Neue Analyse"]
        try store.updateMedia(newerMedia)
        var staleMediaDraft = originalMedia
        staleMediaDraft.tags = ["Alter Editor"]

        XCTAssertThrowsError(
            try store.updateMedia(
                staleMediaDraft,
                expecting: originalMedia
            )
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .mediaChangedExternally
            )
        }
        XCTAssertEqual(
            store.mediaItem(id: originalMedia.id)?.analysisLabels,
            ["Neue Analyse"]
        )
    }

    func testSteckbriefDetailsRoundTrip() throws {
        let person = Person(
            name: "Leni",
            profileDetails: [
                "favoriteColors": ["Blau", "Grün"],
                "custom:Lieblingswort": ["Moin"],
            ]
        )

        let data = try JSONEncoder().encode(person)
        let decoded = try JSONDecoder().decode(Person.self, from: data)

        XCTAssertEqual(decoded.profileDetails["favoriteColors"], ["Blau", "Grün"])
        XCTAssertEqual(decoded.profileDetails["custom:Lieblingswort"], ["Moin"])
    }

    func testProfileColorCodecSupportsNamedAndSpectrumColors() {
        XCTAssertNotNil(ProfileColorCodec.color(for: "Blau"))
        XCTAssertNotNil(ProfileColorCodec.color(for: "#1a334d"))
        XCTAssertNil(ProfileColorCodec.color(for: "#XYZXYZ"))
        XCTAssertEqual(
            ProfileColorCodec.normalizedHex(" #1a334d "),
            "#1A334D"
        )
        XCTAssertEqual(
            ProfileColorCodec.displayName(for: "#1A334D"),
            "Eigene Farbe #1A334D"
        )

        let customColor = Color(
            .sRGB,
            red: 0.1,
            green: 0.2,
            blue: 0.3,
            opacity: 1
        )
        let storedColor = ProfileColorCodec.storageValue(for: customColor)
        XCTAssertNotNil(storedColor)
        XCTAssertNotNil(
            storedColor.flatMap { ProfileColorCodec.normalizedHex($0) }
        )
        XCTAssertNotNil(
            storedColor.flatMap { ProfileColorCodec.color(for: $0) }
        )
    }

    @MainActor
    func testGermanQuestionReturnsSteckbriefDetail() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let person = Person(
            name: "Leni",
            profileDetails: [
                "favoriteColors": ["Blau"],
                "carBrands": ["Volvo"],
            ]
        )
        try store.addPerson(person)

        let colorAnswer = store.answer("Was ist Lenis Lieblingsfarbe?")
        XCTAssertEqual(colorAnswer.kind, .profileDetail)
        XCTAssertEqual(colorAnswer.items.first?.value, "Blau")

        let carAnswer = store.answer("Welche Automarke mag Leni?")
        XCTAssertEqual(carAnswer.kind, .profileDetail)
        XCTAssertEqual(carAnswer.items.first?.value, "Volvo")
    }

    func testProfileLinkRoundTripAndPlatformInference() throws {
        let link = ProfileLink(
            platform: .instagram,
            title: "Foto-Profil",
            url: "instagram.com/leni",
            handle: "leni"
        )
        let person = Person(name: "Leni", links: [link])

        let data = try JSONEncoder().encode(person)
        let decoded = try JSONDecoder().decode(Person.self, from: data)

        XCTAssertEqual(decoded.links.first?.platform, .instagram)
        XCTAssertEqual(decoded.links.first?.resolvedURL?.scheme, "https")
        XCTAssertEqual(
            ProfileLinkPlatform.inferred(
                from: URL(string: "https://www.instagram.com/leni")!
            ),
            .instagram
        )
        XCTAssertEqual(
            ProfileLinkPlatform.inferred(
                from: URL(string: "https://instagram.com.evil.example/leni")!
            ),
            .website
        )
        XCTAssertEqual(
            ProfileLink(platform: .other, url: "https://social.example/leni").kind,
            .socialMedia
        )
    }

    func testPublicResearchURLSafetyBlocksPrivateAndPeopleFinderTargets() {
        XCTAssertTrue(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "https://example.org/profile")!
            )
        )
        XCTAssertFalse(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "https://192.168.1.10/profile")!
            )
        )
        XCTAssertFalse(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "https://www.whitepages.com/person")!
            )
        )
        XCTAssertFalse(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "https://whitepages.com./person")!
            )
        )
        XCTAssertFalse(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "https://2130706433/profile")!
            )
        )
        XCTAssertFalse(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "https://127.1/profile")!
            )
        )
        XCTAssertFalse(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "https://127.0.0.1.nip.io/profile")!
            )
        )
        XCTAssertFalse(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "https://user:secret@example.org/profile")!
            )
        )
        XCTAssertFalse(
            PublicWebResearchService.isSafePublicPageURL(
                URL(string: "http://example.org/profile")!
            )
        )
    }

    func testDuckDuckGoRedirectPreservesEncodedTargetCharacters() throws {
        let target = "https://example.org/a%2Fb?x=one%26two"
        var components = try XCTUnwrap(
            URLComponents(string: "https://duckduckgo.com/l/")
        )
        components.queryItems = [URLQueryItem(name: "uddg", value: target)]
        let redirect = try XCTUnwrap(components.url)

        XCTAssertEqual(
            PublicWebResearchService.duckDuckGoRedirectTarget(from: redirect)?
                .absoluteString,
            target
        )
    }

    func testResearchQueryOnlyUsesApprovedFields() {
        let person = Person(
            name: "Leni Beispiel",
            birthday: Date(timeIntervalSince1970: 0),
            location: "Berlin",
            summary: "Diese Notiz darf nicht gesendet werden.",
            temperamentTags: ["ruhig"],
            interests: ["Fotografie"]
        )

        let withoutLocation = PublicWebResearchService.searchQuery(
            person: person,
            includeLocation: false,
            additionalTerms: "@leni"
        )
        XCTAssertEqual(withoutLocation, #""Leni Beispiel" @leni"#)
        XCTAssertFalse(withoutLocation.contains("Berlin"))
        XCTAssertFalse(withoutLocation.contains("ruhig"))

        let withLocation = PublicWebResearchService.searchQuery(
            person: person,
            includeLocation: true,
            additionalTerms: ""
        )
        XCTAssertEqual(withLocation, #""Leni Beispiel" Berlin"#)
    }

    func testContextResearchBuildsVisibleQueriesWithoutPersonName() {
        let queries = ContextResearchPlanner.queries(
            location: "Schneverdingen",
            clues: ["Badminton", "Badminton", "Fotografie", "Musik", "Kochen"]
        )

        XCTAssertEqual(queries.count, 6)
        XCTAssertEqual(Set(queries.map(\.clue)), Set(["Badminton", "Fotografie", "Musik"]))
        XCTAssertTrue(
            queries.contains {
                $0.text == "Badminton Schneverdingen Verein Club Training"
            }
        )
        XCTAssertTrue(queries.allSatisfy { !$0.text.contains("Leni Beispiel") })
    }

    func testDuckDuckGoFixtureAggregatesReviewablePublicResult() throws {
        let target = "https://verein.example/badminton"
        var redirect = try XCTUnwrap(
            URLComponents(string: "https://duckduckgo.com/l/")
        )
        redirect.queryItems = [URLQueryItem(name: "uddg", value: target)]
        let encodedRedirect = try XCTUnwrap(redirect.url?.absoluteString)
            .replacingOccurrences(of: "&", with: "&amp;")
        let fixture = Data(
            """
            <html><body>
              <a class="result__a" href="\(encodedRedirect)">
                TV Beispiel &amp; Badminton
              </a>
              <a class="result__snippet">Training am Dienstag in der Sporthalle.</a>
            </body></html>
            """.utf8
        )

        let results = PublicWebResearchService.parseDuckDuckGoResponse(fixture)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "TV Beispiel & Badminton")
        XCTAssertEqual(results[0].url.absoluteString, target)
        XCTAssertEqual(
            results[0].excerpt,
            "Training am Dienstag in der Sporthalle."
        )
    }

    func testWikipediaFixtureBecomesReviewableResults() throws {
        let fixture = Data(
            """
            {
              "query": {
                "pages": [
                  {
                    "pageid": 42,
                    "index": 1,
                    "title": "Leni Beispiel",
                    "fullurl": "https://de.wikipedia.org/wiki/Leni_Beispiel",
                    "extract": "  Eine öffentliche Kurzbeschreibung.\\nMit Quelle.  "
                  }
                ]
              }
            }
            """.utf8
        )

        let results = try PublicWebResearchService.parseWikipediaResponse(fixture)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Leni Beispiel")
        XCTAssertEqual(
            results[0].excerpt,
            "Eine öffentliche Kurzbeschreibung. Mit Quelle."
        )
    }

    @MainActor
    func testInvalidProfileLinkIsRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        for value in [
            "javascript://alert",
            "http://example.org/leni",
            "https://127.0.0.1/leni",
            "https://www.whitepages.com/leni"
        ] {
            let person = Person(
                name: "Leni",
                links: [ProfileLink(url: value)]
            )
            XCTAssertThrowsError(try store.addPerson(person), value)
        }
    }

    @MainActor
    func testMutualTriangleCreatesExplainableGroup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let people = [Person(name: "Leni"), Person(name: "Nika"), Person(name: "Mila")]
        for person in people {
            try store.addPerson(person)
        }
        for source in people {
            for target in people where source.id != target.id {
                try store.addRelationshipClaim(from: source.id, to: target.id)
            }
        }

        XCTAssertEqual(store.inferredGroups.count, 1)
        XCTAssertEqual(Set(store.inferredGroups[0].memberIDs), Set(people.map(\.id)))
        XCTAssertTrue(store.inferredGroups[0].explanation.contains("gegenseitig"))
    }

    @MainActor
    func testOneWayClaimsDoNotBecomeFriendship() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let leni = Person(name: "Leni")
        let nika = Person(name: "Nika")
        try store.addPerson(leni)
        try store.addPerson(nika)
        try store.addRelationshipClaim(from: leni.id, to: nika.id)

        XCTAssertTrue(store.mutualFriendIDs(for: leni.id).isEmpty)
        XCTAssertTrue(store.inferredGroups.isEmpty)
    }

    @MainActor
    func testFamilyConnectionsRequireTwoSidesAndStayPairwise() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let elias = Person(name: "Elias")
        let noah = Person(name: "Noah")
        let anna = Person(name: "Anna")
        for person in [elias, noah, anna] {
            try store.addPerson(person)
        }

        try store.addRelationshipClaim(
            from: elias.id,
            to: noah.id,
            kind: .family,
            familyRole: .sibling
        )
        XCTAssertEqual(store.pendingFamilyIDs(for: elias.id), [noah.id])
        XCTAssertTrue(store.mutualFamilyIDs(for: elias.id).isEmpty)

        try store.addRelationshipClaim(
            from: noah.id,
            to: elias.id,
            kind: .family,
            familyRole: .sibling
        )
        XCTAssertEqual(store.mutualFamilyIDs(for: elias.id), [noah.id])
        XCTAssertEqual(store.familyRole(from: elias.id, to: noah.id), .sibling)

        try store.addRelationshipClaim(
            from: elias.id,
            to: anna.id,
            kind: .family,
            familyRole: .cousin
        )
        try store.addRelationshipClaim(
            from: anna.id,
            to: elias.id,
            kind: .family,
            familyRole: .cousin
        )

        XCTAssertEqual(Set(store.mutualFamilyIDs(for: elias.id)), Set([noah.id, anna.id]))
        XCTAssertEqual(store.mutualFamilyIDs(for: noah.id), [elias.id])
        XCTAssertFalse(store.mutualFamilyIDs(for: noah.id).contains(anna.id))
        XCTAssertTrue(store.mutualFriendIDs(for: elias.id).isEmpty)
        XCTAssertTrue(store.inferredGroups.isEmpty)
    }

    func testFamilyRoleProvidesCorrectInverse() {
        XCTAssertEqual(FamilyRelationshipRole.parent.inverse, .child)
        XCTAssertEqual(FamilyRelationshipRole.grandchild.inverse, .grandparent)
        XCTAssertEqual(FamilyRelationshipRole.sibling.inverse, .sibling)
    }

    @MainActor
    func testManualRelationshipPairCanBeEditedAndDeletedAtomically() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let elias = Person(name: "Elias")
        let noah = Person(name: "Noah")
        try store.addPerson(elias)
        try store.addPerson(noah)

        try store.setRelationshipPair(
            from: elias.id,
            to: noah.id,
            kind: .family,
            familyRole: .parent,
            mutual: true,
            notes: "Manuell gepflegt"
        )

        XCTAssertEqual(store.data.relationshipClaims.count, 2)
        XCTAssertEqual(store.familyRole(from: elias.id, to: noah.id), .parent)
        XCTAssertEqual(store.familyRole(from: noah.id, to: elias.id), .child)
        XCTAssertTrue(store.data.relationshipClaims.allSatisfy { $0.source == .manual })

        let familyBaseline = store.data.relationshipClaims
        try store.setRelationshipPair(
            from: elias.id,
            to: noah.id,
            kind: .friendship,
            mutual: false,
            replacingKind: .family,
            expecting: familyBaseline
        )

        XCTAssertEqual(store.data.relationshipClaims.count, 1)
        XCTAssertEqual(store.data.relationshipClaims.first?.kind, .friendship)
        XCTAssertTrue(store.mutualFriendIDs(for: elias.id).isEmpty)

        let friendshipBaseline = store.data.relationshipClaims
        try store.deleteRelationshipPair(
            between: elias.id,
            and: noah.id,
            kind: .friendship,
            expecting: friendshipBaseline
        )
        XCTAssertTrue(store.data.relationshipClaims.isEmpty)
    }

    @MainActor
    func testRelationshipTypeChangeDoesNotDeleteExistingTargetType() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let elias = Person(name: "Elias")
        let noah = Person(name: "Noah")
        try store.addPerson(elias)
        try store.addPerson(noah)
        try store.setRelationshipPair(
            from: elias.id,
            to: noah.id,
            kind: .family,
            familyRole: .sibling,
            mutual: true,
            notes: "Familie"
        )
        try store.setRelationshipPair(
            from: elias.id,
            to: noah.id,
            kind: .friendship,
            mutual: true,
            notes: "Freunde"
        )

        XCTAssertThrowsError(
            try store.setRelationshipPair(
                from: elias.id,
                to: noah.id,
                kind: .friendship,
                mutual: false,
                replacingKind: .family
            )
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .relationshipKindConflict
            )
        }
        XCTAssertEqual(
            store.relationshipClaims.filter { $0.kind == .family }.count,
            2
        )
        XCTAssertEqual(
            store.relationshipClaims.filter { $0.kind == .friendship }.count,
            2
        )
    }

    @MainActor
    func testStaleRelationshipPairDraftCannotOverwriteOrDeleteNewerClaims() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let elias = Person(name: "Elias")
        let noah = Person(name: "Noah")
        try store.addPerson(elias)
        try store.addPerson(noah)
        try store.setRelationshipPair(
            from: elias.id,
            to: noah.id,
            kind: .friendship,
            mutual: true,
            notes: "Alter Stand"
        )
        let staleBaseline = store.data.relationshipClaims

        var externallyChanged = try XCTUnwrap(
            store.data.relationshipClaims.first
        )
        externallyChanged.notes = "Neu von Codex"
        try store.updateRelationshipClaim(externallyChanged)

        XCTAssertThrowsError(
            try store.setRelationshipPair(
                from: elias.id,
                to: noah.id,
                kind: .friendship,
                mutual: false,
                notes: "Alter Editor",
                expecting: staleBaseline
            )
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .relationshipChangedExternally
            )
        }
        XCTAssertThrowsError(
            try store.deleteRelationshipPair(
                between: elias.id,
                and: noah.id,
                kind: .friendship,
                expecting: staleBaseline
            )
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .relationshipChangedExternally
            )
        }
        XCTAssertEqual(store.data.relationshipClaims.count, 2)
        XCTAssertTrue(
            store.data.relationshipClaims.contains {
                $0.id == externallyChanged.id
                    && $0.notes == "Neu von Codex"
            }
        )
    }

    @MainActor
    func testStaleRelationshipTypeChangeCannotOverwriteNewTargetKind() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let elias = Person(name: "Elias")
        let noah = Person(name: "Noah")
        try store.addPerson(elias)
        try store.addPerson(noah)
        try store.setRelationshipPair(
            from: elias.id,
            to: noah.id,
            kind: .family,
            familyRole: .sibling,
            mutual: true
        )
        let staleBaseline = store.data.relationshipClaims
        try store.setRelationshipPair(
            from: elias.id,
            to: noah.id,
            kind: .friendship,
            mutual: true
        )

        XCTAssertThrowsError(
            try store.setRelationshipPair(
                from: elias.id,
                to: noah.id,
                kind: .friendship,
                mutual: false,
                replacingKind: .family,
                expecting: staleBaseline
            )
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .relationshipChangedExternally
            )
        }
        XCTAssertEqual(
            store.data.relationshipClaims.filter { $0.kind == .family }.count,
            2
        )
        XCTAssertEqual(
            store.data.relationshipClaims.filter { $0.kind == .friendship }.count,
            2
        )
    }

    @MainActor
    func testStaleGroupDraftCannotOverwriteOrDeleteNewerGroup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let people = [Person(name: "Elias"), Person(name: "Noah")]
        for person in people {
            try store.addPerson(person)
        }
        let original = Group(
            name: "Alter Name",
            memberIDs: people.map(\.id)
        )
        try store.addGroup(original)

        var newerGroup = original
        newerGroup.name = "Neu von Codex"
        try store.updateGroup(newerGroup)

        var staleDraft = original
        staleDraft.name = "Alter Editor"
        XCTAssertThrowsError(
            try store.updateGroup(staleDraft, expecting: original)
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .groupChangedExternally
            )
        }
        XCTAssertThrowsError(
            try store.deleteGroup(id: original.id, expecting: original)
        ) {
            XCTAssertEqual(
                $0 as? LibraryStoreError,
                .groupChangedExternally
            )
        }
        let current = try XCTUnwrap(
            store.data.groups.first { $0.id == original.id }
        )
        XCTAssertEqual(current.name, "Neu von Codex")

        try store.deleteGroup(id: current.id, expecting: current)
        XCTAssertFalse(store.data.groups.contains { $0.id == original.id })
    }

    @MainActor
    func testManualGroupImmediatelyReplacesEquivalentAutomaticSuggestion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let people = [Person(name: "A"), Person(name: "B"), Person(name: "C")]
        for person in people {
            try store.addPerson(person)
        }
        for source in people {
            for target in people where source.id != target.id {
                try store.addRelationshipClaim(from: source.id, to: target.id)
            }
        }
        XCTAssertEqual(store.inferredGroups.count, 1)

        try store.addGroup(
            Group(
                name: "Meine Gruppe",
                memberIDs: people.map(\.id),
                status: .manual
            )
        )

        XCTAssertTrue(store.inferredGroups.isEmpty)
        XCTAssertEqual(store.data.groups.filter { $0.status == .manual }.map(\.name), ["Meine Gruppe"])
    }

    @MainActor
    func testProfileImageMustBeAnAssignedImageAndCanBeRemoved() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let elias = Person(name: "Elias")
        let noah = Person(name: "Noah")
        try store.addPerson(elias)
        try store.addPerson(noah)

        let image = MediaItem(
            storedFilename: "elias.jpg",
            originalFilename: "Elias.jpg",
            kind: .image,
            personIDs: [elias.id]
        )
        let video = MediaItem(
            storedFilename: "elias.mov",
            originalFilename: "Elias.mov",
            kind: .video,
            personIDs: [elias.id]
        )
        let foreignImage = MediaItem(
            storedFilename: "noah.jpg",
            originalFilename: "Noah.jpg",
            kind: .image,
            personIDs: [noah.id]
        )
        try store.addMedia(image)
        try store.addMedia(video)
        try store.addMedia(foreignImage)

        try store.setAvatarMediaID(image.id, for: elias.id)
        XCTAssertEqual(store.person(id: elias.id)?.avatarMediaID, image.id)

        var reassignedImage = image
        reassignedImage.personIDs = [noah.id]
        try store.updateMedia(reassignedImage)
        XCTAssertNil(store.person(id: elias.id)?.avatarMediaID)

        XCTAssertThrowsError(try store.setAvatarMediaID(video.id, for: elias.id))
        XCTAssertThrowsError(try store.setAvatarMediaID(foreignImage.id, for: elias.id))

        try store.setAvatarMediaID(nil, for: elias.id)
        XCTAssertNil(store.person(id: elias.id)?.avatarMediaID)
        XCTAssertNotNil(store.mediaItem(id: image.id))
    }

    func testProfileImageCropGeometryKeepsTheSquareInsideTheImage() {
        let centered = ProfileImageCropGeometry.sourceRect(
            imageSize: CGSize(width: 1_200, height: 800),
            viewportSide: 400,
            zoom: 1,
            offset: .zero
        )
        XCTAssertEqual(centered.origin.x, 200, accuracy: 0.001)
        XCTAssertEqual(centered.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(centered.width, 800, accuracy: 0.001)

        let draggedPastEdge = ProfileImageCropGeometry.sourceRect(
            imageSize: CGSize(width: 1_200, height: 800),
            viewportSide: 400,
            zoom: 1,
            offset: CGSize(width: 10_000, height: 10_000)
        )
        XCTAssertEqual(draggedPastEdge.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(draggedPastEdge.origin.y, 0, accuracy: 0.001)

        let zoomed = ProfileImageCropGeometry.sourceRect(
            imageSize: CGSize(width: 1_200, height: 800),
            viewportSide: 400,
            zoom: 2,
            offset: .zero
        )
        XCTAssertEqual(zoomed.origin.x, 400, accuracy: 0.001)
        XCTAssertEqual(zoomed.origin.y, 200, accuracy: 0.001)
        XCTAssertEqual(zoomed.width, 400, accuracy: 0.001)
    }

    @MainActor
    func testProfileImageCropRendererCreatesSquarePNG() throws {
        let image = NSImage(size: NSSize(width: 1_200, height: 800))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 1_200, height: 800).fill()
        image.unlockFocus()

        let data = try ProfileImageCropRenderer.pngData(
            from: image,
            viewportSide: 400,
            zoom: 1.5,
            offset: CGSize(width: 35, height: -20),
            outputPixels: 128
        )
        let rendered = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(rendered.pixelsWide, 128)
        XCTAssertEqual(rendered.pixelsHigh, 128)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4e, 0x47])
    }

    @MainActor
    func testImportCroppedProfileImageStoresCopyAndSelectsItAtomically() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let person = Person(name: "Elias")
        try store.addPerson(person)

        let pngData = try validPNGData()
        let cropped = try store.importCroppedProfileImage(
            pngData: pngData,
            originalFilename: "Urlaub.heic",
            for: person.id
        )

        XCTAssertEqual(cropped.kind, .image)
        XCTAssertEqual(cropped.originalFilename, "Urlaub-Profilbild.png")
        XCTAssertEqual(cropped.personIDs, [person.id])
        XCTAssertTrue(cropped.tags.contains("Profilbild-Zuschnitt"))
        XCTAssertEqual(store.person(id: person.id)?.avatarMediaID, cropped.id)
        let storedData = try Data(
            contentsOf: store.mediaURL(for: cropped)
        )
        let storedBitmap = try XCTUnwrap(
            NSBitmapImageRep(data: storedData)
        )
        XCTAssertEqual(storedBitmap.pixelsWide, 12)
        XCTAssertEqual(storedBitmap.pixelsHigh, 12)
    }

    @MainActor
    func testCameraProfileImageStoresOnlyCroppedMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let person = Person(name: "Elias")
        try store.addPerson(person)
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let taggedPNG = try pngDataWithDescription(
            "Private Kamera-Notiz"
        )
        let cropped = try store.importCroppedProfileImage(
            pngData: taggedPNG,
            originalFilename: "Kameraaufnahme-20260727-120000",
            for: person.id,
            source: .camera,
            capturedAt: capturedAt
        )

        XCTAssertEqual(cropped.capturedAt, capturedAt)
        XCTAssertEqual(
            cropped.tags,
            ["Profilbild-Zuschnitt", "Kameraaufnahme"]
        )
        XCTAssertTrue(cropped.notes.contains("nur der quadratische"))
        XCTAssertFalse(cropped.notes.localizedCaseInsensitiveContains("gerät"))
        XCTAssertEqual(store.person(id: person.id)?.avatarMediaID, cropped.id)

        let storedURL = store.mediaURL(for: cropped)
        let storedData = try Data(contentsOf: storedURL)
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(storedData as CFData, nil)
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any]
        )
        let pngProperties =
            properties[kCGImagePropertyPNGDictionary]
                as? [CFString: Any]
        XCTAssertNil(pngProperties?[kCGImagePropertyPNGDescription])

        let attributes = try FileManager.default.attributesOfItem(
            atPath: storedURL.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    @MainActor
    func testCroppedProfileImportRejectsJPEGAndNonSquarePNG() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let person = Person(name: "Noah")
        try store.addPerson(person)

        XCTAssertThrowsError(
            try store.importCroppedProfileImage(
                pngData: validJPEGData(),
                originalFilename: "Foto.jpg",
                for: person.id
            )
        )
        XCTAssertThrowsError(
            try store.importCroppedProfileImage(
                pngData: validPNGData(width: 12, height: 8),
                originalFilename: "Nicht-quadratisch.png",
                for: person.id
            )
        )
        XCTAssertTrue(store.mediaItems.isEmpty)
        XCTAssertNil(store.person(id: person.id)?.avatarMediaID)
    }

    @MainActor
    func testGermanQueryReturnsVisualAgeAnswer() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let calendar = Calendar(identifier: .gregorian)
        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let leni = Person(
            name: "Leni",
            birthday: calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))
        )
        try store.addPerson(leni)

        let answer = store.answer("Wie alt ist Leni?")
        XCTAssertEqual(answer.kind, .age)
        XCTAssertEqual(answer.personIDs.first, leni.id)
        XCTAssertFalse(answer.items.isEmpty)
    }

    @MainActor
    func testGermanQueryReturnsConfirmedSocialLinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let leni = Person(
            name: "Leni",
            links: [
                ProfileLink(
                    platform: .instagram,
                    url: "https://instagram.com/leni",
                    handle: "@leni",
                    confirmed: true
                ),
                ProfileLink(
                    title: "Noch unsicher",
                    url: "https://example.org/leni",
                    confirmed: false
                )
            ]
        )
        try store.addPerson(leni)

        let answer = store.answer("Welche Social-Media-Links hat Leni?")
        XCTAssertEqual(answer.kind, .links)
        XCTAssertEqual(answer.items.count, 1)
        XCTAssertTrue(answer.items[0].value.contains("instagram.com/leni"))
        XCTAssertFalse(answer.items[0].value.contains("example.org"))

        let genitiveAnswer = store.answer("Wie lautet Lenis Instagram-Link?")
        XCTAssertEqual(genitiveAnswer.kind, .links)
        XCTAssertEqual(genitiveAnswer.items.count, 1)

        let overview = store.answer("Wer ist Leni?")
        let onlineItem = try XCTUnwrap(
            overview.items.first { $0.label == "Online" }
        )
        XCTAssertEqual(onlineItem.value, "Instagram")
    }

    @MainActor
    func testAmbiguousFirstNameDoesNotChooseAPersonSilently() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        try store.addPerson(Person(name: "Leni Nord"))
        try store.addPerson(Person(name: "Leni Süd"))

        let ambiguous = store.answer("Wie alt ist Leni?")
        XCTAssertEqual(ambiguous.kind, .notFound)
        XCTAssertTrue(ambiguous.title.localizedCaseInsensitiveContains("mehrdeutig"))

        let exact = store.answer("Wie alt ist Leni Nord?")
        XCTAssertEqual(exact.kind, .age)
    }

    @MainActor
    func testRejectedGroupIsNotSuggestedAgain() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let people = [Person(name: "A"), Person(name: "B"), Person(name: "C")]
        for person in people { try store.addPerson(person) }
        for source in people {
            for target in people where source.id != target.id {
                try store.addRelationshipClaim(from: source.id, to: target.id)
            }
        }

        var rejected = try XCTUnwrap(store.inferredGroups.first)
        rejected.status = .rejected
        try store.updateGroup(rejected)
        _ = try store.inferFriendshipGroups()

        XCTAssertTrue(store.inferredGroups.isEmpty)
        XCTAssertEqual(store.data.groups.filter { $0.status == .rejected }.count, 1)
    }

    @MainActor
    func testClothingPatternNeedsThreeConfirmedMediaItems() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freundeblick-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let person = Person(name: "Nika")
        try store.addPerson(person)

        for index in 1...3 {
            try store.addMedia(
                MediaItem(
                    storedFilename: "\(index).jpg",
                    originalFilename: "\(index).jpg",
                    kind: .image,
                    personIDs: [person.id],
                    clothingTags: ["Jacke"]
                )
            )
        }
        try store.refreshConfirmedClothingPatterns(for: [person.id])

        let observation = try XCTUnwrap(
            store.data.observations.first {
                $0.personID == person.id && $0.category == .clothing
            }
        )
        XCTAssertEqual(observation.status, .likely)
        XCTAssertEqual(observation.source, .mediaAnalysis)
        XCTAssertEqual(observation.evidenceMediaIDs.count, 3)

        var changedMedia = try XCTUnwrap(store.data.media.first)
        changedMedia.clothingTags = []
        try store.updateMedia(changedMedia)
        try store.refreshConfirmedClothingPatterns(for: [person.id])

        XCTAssertEqual(
            store.data.observations.first { $0.id == observation.id }?.status,
            .archived
        )
    }

    @MainActor
    func testDeletingEvidenceMediaRefreshesDerivedClothingPattern() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let person = Person(name: "Nika")
        try store.addPerson(person)

        var mediaIDs: [UUID] = []
        for index in 1 ... 3 {
            let item = MediaItem(
                storedFilename: "\(index).jpg",
                originalFilename: "\(index).jpg",
                kind: .image,
                personIDs: [person.id],
                clothingTags: ["Jacke"]
            )
            mediaIDs.append(item.id)
            try store.addMedia(item)
        }
        try store.refreshConfirmedClothingPatterns(for: [person.id])
        let patternID = try XCTUnwrap(
            store.observations.first {
                $0.personID == person.id
                    && $0.source == .mediaAnalysis
                    && $0.status == .likely
            }?.id
        )

        try store.deleteMedia(id: try XCTUnwrap(mediaIDs.first))

        let archived = try XCTUnwrap(
            store.observations.first { $0.id == patternID }
        )
        XCTAssertEqual(archived.status, .archived)
        XCTAssertFalse(archived.evidenceMediaIDs.contains(mediaIDs[0]))
    }

    @MainActor
    func testFailedMediaAnalysisKeepsExistingLabels() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "freundeblick-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(
            databaseURL: root.appendingPathComponent("friends.json"),
            mediaDirectory: root.appendingPathComponent("media")
        )
        let item = MediaItem(
            storedFilename: "fehlt.jpg",
            originalFilename: "Fehlt.jpg",
            kind: .image,
            analysisLabels: ["Vorhandene Analyse"]
        )
        try store.addMedia(item)

        do {
            try await store.analyzeMediaItem(id: item.id)
            XCTFail("Eine fehlende Datei muss als Analysefehler gemeldet werden.")
        } catch {
            XCTAssertEqual(
                error as? LocalMediaAnalyzerError,
                .unreadableMedia
            )
        }
        XCTAssertEqual(
            store.mediaItem(id: item.id)?.analysisLabels,
            ["Vorhandene Analyse"]
        )
    }

    private func pendingMediaDeletionJournal(
        mediaID: UUID,
        storedFilename: String
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "mediaID": mediaID.uuidString,
                "storedFilename": storedFilename,
            ],
            options: [.sortedKeys]
        )
    }

    @MainActor
    private func validPNGData(
        width: Int = 12,
        height: Int = 12
    ) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw XCTSkip("Testbild konnte nicht erzeugt werden.")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(
            using: .png,
            properties: [:]
        )
        else {
            throw XCTSkip("Testbild konnte nicht erzeugt werden.")
        }
        return png
    }

    @MainActor
    private func validJPEGData() throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            data: try validPNGData()
        ),
              let jpeg = bitmap.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: 0.85]
              )
        else {
            throw XCTSkip("JPEG-Testbild konnte nicht erzeugt werden.")
        }
        return jpeg
    }

    @MainActor
    private func pngDataWithDescription(
        _ description: String
    ) throws -> Data {
        let plainPNG = try validPNGData()
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(plainPNG as CFData, nil)
        )
        let taggedData = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                taggedData,
                "public.png" as CFString,
                1,
                nil
            )
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGDescription: description,
            ],
        ]
        CGImageDestinationAddImageFromSource(
            destination,
            source,
            0,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("PNG-Metadaten konnten nicht erzeugt werden.")
        }
        return taggedData as Data
    }
}
