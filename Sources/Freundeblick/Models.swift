import Foundation

// MARK: - Shared value types

public enum RelationshipKind: String, Codable, CaseIterable, Sendable {
    case friendship
    case family
    case romantic
    case school
    case work
    case acquaintance
    case other

    public var germanLabel: String {
        switch self {
        case .friendship: "Freundschaft"
        case .family: "Familie"
        case .romantic: "Partnerschaft"
        case .school: "Schule"
        case .work: "Arbeit"
        case .acquaintance: "Bekanntschaft"
        case .other: "Andere"
        }
    }
}

/// Describes how the target person is related to the person making a family claim.
///
/// Family links stay pairwise. The inverse is only used when both sides are saved at once;
/// it never creates additional links to other relatives.
public enum FamilyRelationshipRole: String, Codable, CaseIterable, Sendable {
    case familyMember
    case parent
    case child
    case sibling
    case grandparent
    case grandchild
    case auntUncle
    case nieceNephew
    case cousin
    case spouse
    case stepfamily
    case inLaw

    public var germanLabel: String {
        switch self {
        case .familyMember: "Familienmitglied"
        case .parent: "Elternteil"
        case .child: "Kind"
        case .sibling: "Geschwister"
        case .grandparent: "Großelternteil"
        case .grandchild: "Enkelkind"
        case .auntUncle: "Tante oder Onkel"
        case .nieceNephew: "Nichte oder Neffe"
        case .cousin: "Cousin oder Cousine"
        case .spouse: "Ehepartner oder Ehepartnerin"
        case .stepfamily: "Stieffamilie"
        case .inLaw: "Angeheiratete Familie"
        }
    }

    public var inverse: FamilyRelationshipRole {
        switch self {
        case .parent: .child
        case .child: .parent
        case .grandparent: .grandchild
        case .grandchild: .grandparent
        case .auntUncle: .nieceNephew
        case .nieceNephew: .auntUncle
        case .familyMember, .sibling, .cousin, .spouse, .stepfamily, .inLaw: self
        }
    }
}

public enum RelationshipStatus: String, Codable, CaseIterable, Sendable {
    case claimed
    case confirmed
    case disputed
    case rejected
    case ended

    public var supportsInference: Bool {
        self == .claimed || self == .confirmed
    }
}

public enum EvidenceSource: String, Codable, CaseIterable, Sendable {
    case manual
    case personStatement
    case mediaAnalysis
    case inferred
    case imported

    public var germanLabel: String {
        switch self {
        case .manual: "Manuell eingetragen"
        case .personStatement: "Aussage der Person"
        case .mediaAnalysis: "Aus Foto oder Video"
        case .inferred: "Automatisch abgeleitet"
        case .imported: "Importiert"
        }
    }
}

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case image
    case video
}

public enum ProfileImageImportSource: String, Equatable, Sendable {
    case file
    case existingMedia
    case camera
    case iPhoneImport
}

public enum GroupStatus: String, Codable, CaseIterable, Sendable {
    case manual
    case inferred
    case rejected
    case archived

    public var isVisible: Bool {
        self == .manual || self == .inferred
    }
}

public enum ObservationCategory: String, Codable, CaseIterable, Sendable {
    case identity
    case location
    case personality
    case clothing
    case appearance
    case interest
    case preference
    case habit
    case biography
    case other

    public var germanLabel: String {
        switch self {
        case .identity: "Identität"
        case .location: "Wohnort"
        case .personality: "Charakter"
        case .clothing: "Kleidung"
        case .appearance: "Aussehen"
        case .interest: "Interesse"
        case .preference: "Vorliebe"
        case .habit: "Gewohnheit"
        case .biography: "Biografie"
        case .other: "Notiz"
        }
    }
}

public enum ObservationStatus: String, Codable, CaseIterable, Sendable {
    case unverified
    case likely
    case confirmed
    case disputed
    case archived

    public var isVisibleByDefault: Bool {
        self != .archived
    }
}

public enum ProfileLinkKind: String, Codable, CaseIterable, Sendable {
    case website
    case socialMedia

    public var germanLabel: String {
        switch self {
        case .website: "Webseite"
        case .socialMedia: "Social Media"
        }
    }
}

public enum ProfileLinkPlatform: String, Codable, CaseIterable, Sendable {
    case website
    case instagram
    case tiktok
    case youtube
    case linkedin
    case x
    case facebook
    case snapchat
    case threads
    case mastodon
    case github
    case other

    public var germanLabel: String {
        switch self {
        case .website: "Webseite"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .linkedin: "LinkedIn"
        case .x: "X"
        case .facebook: "Facebook"
        case .snapchat: "Snapchat"
        case .threads: "Threads"
        case .mastodon: "Mastodon"
        case .github: "GitHub"
        case .other: "Andere"
        }
    }

    public var kind: ProfileLinkKind {
        self == .website ? .website : .socialMedia
    }

    public var symbolName: String {
        switch self {
        case .website: "globe"
        case .instagram: "camera.circle.fill"
        case .tiktok: "music.note"
        case .youtube: "play.rectangle.fill"
        case .linkedin: "person.text.rectangle.fill"
        case .x: "bubble.left.and.bubble.right.fill"
        case .facebook: "person.2.circle.fill"
        case .snapchat: "message.fill"
        case .threads: "at.circle.fill"
        case .mastodon: "quote.bubble.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .other: "link"
        }
    }

    public static func inferred(from url: URL) -> ProfileLinkPlatform {
        let host = (url.host ?? "").lowercased()
        func matches(_ domain: String) -> Bool {
            host == domain || host.hasSuffix(".\(domain)")
        }

        if matches("instagram.com") { return .instagram }
        if matches("tiktok.com") { return .tiktok }
        if matches("youtube.com") || matches("youtu.be") { return .youtube }
        if matches("linkedin.com") { return .linkedin }
        if matches("x.com") || matches("twitter.com") { return .x }
        if matches("facebook.com") { return .facebook }
        if matches("snapchat.com") { return .snapchat }
        if matches("threads.net") { return .threads }
        if matches("mastodon.social") || matches("mastodon.online") { return .mastodon }
        if matches("github.com") { return .github }
        return .website
    }
}

public struct ProfileLink: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: ProfileLinkKind
    public var platform: ProfileLinkPlatform
    public var title: String
    public var url: String
    public var handle: String
    public var confirmed: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ProfileLinkKind? = nil,
        platform: ProfileLinkPlatform = .website,
        title: String = "",
        url: String,
        handle: String = "",
        confirmed: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind ?? platform.kind
        self.platform = platform
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.handle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.confirmed = confirmed
        self.createdAt = createdAt
    }

    public var displayTitle: String {
        if !title.isEmpty { return title }
        if !handle.isEmpty { return handle.hasPrefix("@") ? handle : "@\(handle)" }
        return platform.germanLabel
    }

    public var resolvedURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }

        guard let resolved = URL(string: candidate),
              let scheme = resolved.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = resolved.host,
              !host.isEmpty,
              resolved.user == nil,
              resolved.password == nil
        else {
            return nil
        }
        return resolved
    }
}

// MARK: - Persisted models

public struct Person: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var aliases: [String]
    public var birthday: Date?
    public var location: String?
    public var summary: String
    public var temperamentTags: [String]
    public var interests: [String]
    public var profileDetails: [String: [String]]
    public var links: [ProfileLink]
    public var avatarMediaID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        birthday: Date? = nil,
        location: String? = nil,
        summary: String = "",
        temperamentTags: [String] = [],
        interests: [String] = [],
        profileDetails: [String: [String]] = [:],
        links: [ProfileLink] = [],
        avatarMediaID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliases = aliases
        self.birthday = birthday
        self.location = location
        self.summary = summary
        self.temperamentTags = temperamentTags
        self.interests = interests
        self.profileDetails = profileDetails
        self.links = links
        self.avatarMediaID = avatarMediaID
        self.createdAt = createdAt
    }

    public func age(on date: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let birthday, birthday <= date else { return nil }
        return calendar.dateComponents([.year], from: birthday, to: date).year
    }

    public var allNames: [String] {
        [name] + aliases
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case aliases
        case birthday
        case location
        case summary
        case temperamentTags
        case interests
        case profileDetails
        case links
        case avatarMediaID
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        birthday = try container.decodeIfPresent(Date.self, forKey: .birthday)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        temperamentTags = try container.decodeIfPresent(
            [String].self,
            forKey: .temperamentTags
        ) ?? []
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        profileDetails = try container.decodeIfPresent(
            [String: [String]].self,
            forKey: .profileDetails
        ) ?? [:]
        links = try container.decodeIfPresent([ProfileLink].self, forKey: .links) ?? []
        avatarMediaID = try container.decodeIfPresent(UUID.self, forKey: .avatarMediaID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(aliases, forKey: .aliases)
        try container.encodeIfPresent(birthday, forKey: .birthday)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(summary, forKey: .summary)
        try container.encode(temperamentTags, forKey: .temperamentTags)
        try container.encode(interests, forKey: .interests)
        try container.encode(profileDetails, forKey: .profileDetails)
        try container.encode(links, forKey: .links)
        try container.encodeIfPresent(avatarMediaID, forKey: .avatarMediaID)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

/// A directed statement: `fromPersonID` says that a relationship to `toPersonID` exists.
public struct RelationshipClaim: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var fromPersonID: UUID
    public var toPersonID: UUID
    public var kind: RelationshipKind
    public var familyRole: FamilyRelationshipRole?
    public var status: RelationshipStatus
    public var source: EvidenceSource
    public var notes: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        fromPersonID: UUID,
        toPersonID: UUID,
        kind: RelationshipKind = .friendship,
        familyRole: FamilyRelationshipRole? = nil,
        status: RelationshipStatus = .claimed,
        source: EvidenceSource = .personStatement,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromPersonID = fromPersonID
        self.toPersonID = toPersonID
        self.kind = kind
        self.familyRole = kind == .family ? familyRole : nil
        self.status = status
        self.source = source
        self.notes = notes
        self.createdAt = createdAt
    }
}

public struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var storedFilename: String
    public var originalFilename: String
    public var kind: MediaKind
    public var personIDs: [UUID]
    public var importedAt: Date
    public var capturedAt: Date?
    public var tags: [String]
    public var clothingTags: [String]
    public var notes: String
    public var analysisLabels: [String]

    public init(
        id: UUID = UUID(),
        storedFilename: String,
        originalFilename: String,
        kind: MediaKind,
        personIDs: [UUID] = [],
        importedAt: Date = Date(),
        capturedAt: Date? = nil,
        tags: [String] = [],
        clothingTags: [String] = [],
        notes: String = "",
        analysisLabels: [String] = []
    ) {
        self.id = id
        self.storedFilename = storedFilename
        self.originalFilename = originalFilename
        self.kind = kind
        self.personIDs = personIDs
        self.importedAt = importedAt
        self.capturedAt = capturedAt
        self.tags = tags
        self.clothingTags = clothingTags
        self.notes = notes
        self.analysisLabels = analysisLabels
    }
}

public struct Group: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var memberIDs: [UUID]
    public var status: GroupStatus
    public var confidence: Double
    public var explanation: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        memberIDs: [UUID],
        status: GroupStatus = .manual,
        confidence: Double = 1,
        explanation: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.status = status
        self.confidence = min(max(confidence, 0), 1)
        self.explanation = explanation
        self.createdAt = createdAt
    }
}

public struct Observation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var personID: UUID
    public var category: ObservationCategory
    public var value: String
    public var status: ObservationStatus
    public var confidence: Double
    public var source: EvidenceSource
    public var evidenceMediaIDs: [UUID]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        personID: UUID,
        category: ObservationCategory,
        value: String,
        status: ObservationStatus = .unverified,
        confidence: Double = 0.5,
        source: EvidenceSource = .manual,
        evidenceMediaIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.personID = personID
        self.category = category
        self.value = value
        self.status = status
        self.confidence = min(max(confidence, 0), 1)
        self.source = source
        self.evidenceMediaIDs = evidenceMediaIDs
        self.createdAt = createdAt
    }
}

/// `Fact` is an alternative domain name for an observation, kept as a source-compatible alias.
public typealias Fact = Observation

public struct LibraryData: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var people: [Person]
    public var relationshipClaims: [RelationshipClaim]
    public var groups: [Group]
    public var media: [MediaItem]
    public var observations: [Observation]
    public var lastUpdated: Date

    public init(
        schemaVersion: Int = LibraryData.currentSchemaVersion,
        people: [Person] = [],
        relationshipClaims: [RelationshipClaim] = [],
        groups: [Group] = [],
        media: [MediaItem] = [],
        observations: [Observation] = [],
        lastUpdated: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.people = people
        self.relationshipClaims = relationshipClaims
        self.groups = groups
        self.media = media
        self.observations = observations
        self.lastUpdated = lastUpdated
    }

    // Readable aliases for callers that use the longer domain names.
    public var persons: [Person] {
        get { people }
        set { people = newValue }
    }

    public var mediaItems: [MediaItem] {
        get { media }
        set { media = newValue }
    }
}

// MARK: - Structured query answers

public enum QueryAnswerKind: String, Codable, Sendable {
    case personOverview
    case age
    case location
    case friends
    case groups
    case personality
    case profileDetail
    case clothing
    case media
    case links
    case searchResults
    case notFound
}

public struct QueryAnswerItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var label: String
    public var value: String
    public var symbolName: String
    public var confidence: Double?

    public init(
        id: UUID = UUID(),
        label: String,
        value: String,
        symbolName: String,
        confidence: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.symbolName = symbolName
        self.confidence = confidence.map { min(max($0, 0), 1) }
    }
}

/// A presentation-neutral result. The UI can render the referenced people, media and groups as cards.
public struct QueryAnswer: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: QueryAnswerKind
    public var title: String
    public var subtitle: String?
    public var items: [QueryAnswerItem]
    public var personIDs: [UUID]
    public var mediaIDs: [UUID]
    public var groupIDs: [UUID]

    public init(
        id: UUID = UUID(),
        kind: QueryAnswerKind,
        title: String,
        subtitle: String? = nil,
        items: [QueryAnswerItem] = [],
        personIDs: [UUID] = [],
        mediaIDs: [UUID] = [],
        groupIDs: [UUID] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.personIDs = personIDs
        self.mediaIDs = mediaIDs
        self.groupIDs = groupIDs
    }
}
