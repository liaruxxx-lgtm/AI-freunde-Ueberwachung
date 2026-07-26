import AppKit
import Foundation
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
        XCTAssertEqual(
            Set(
                ComparisonEngine.comparableProfileValues([
                    "favoriteColors": ["Blau"],
                    "genderIdentity": ["nichtbinär"],
                    "sexualOrientation": ["bisexuell"],
                ])
            ),
            Set(["Blau"])
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

    func testLegacyPersonWithoutLinksStillDecodes() throws {
        let data = Data(#"{"name":"Leni"}"#.utf8)
        let person = try JSONDecoder().decode(Person.self, from: data)

        XCTAssertEqual(person.name, "Leni")
        XCTAssertTrue(person.links.isEmpty)
        XCTAssertTrue(person.profileDetails.isEmpty)
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
            "Eigene Farbe"
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

        try store.setRelationshipPair(
            from: elias.id,
            to: noah.id,
            kind: .friendship,
            mutual: false,
            replacingKind: .family
        )

        XCTAssertEqual(store.data.relationshipClaims.count, 1)
        XCTAssertEqual(store.data.relationshipClaims.first?.kind, .friendship)
        XCTAssertTrue(store.mutualFriendIDs(for: elias.id).isEmpty)

        try store.deleteRelationshipPair(
            between: elias.id,
            and: noah.id,
            kind: .friendship
        )
        XCTAssertTrue(store.data.relationshipClaims.isEmpty)
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

        let pngData = Data([0x89, 0x50, 0x4e, 0x47])
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
        XCTAssertEqual(
            try Data(contentsOf: store.mediaURL(for: cropped)),
            pngData
        )
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
    }
}
