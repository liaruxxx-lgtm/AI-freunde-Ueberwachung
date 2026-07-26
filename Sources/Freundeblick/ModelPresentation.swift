import Foundation

extension RelationshipKind {
    var displayName: String { germanLabel }
}

extension EvidenceSource {
    var displayName: String { germanLabel }
}

extension QueryAnswer {
    var systemImage: String {
        switch kind {
        case .personOverview: "person.text.rectangle"
        case .age: "birthday.cake.fill"
        case .location: "location.fill"
        case .friends: "person.2.fill"
        case .groups: "person.3.fill"
        case .personality: "heart.text.square.fill"
        case .profileDetail: "list.bullet.clipboard.fill"
        case .clothing: "tshirt.fill"
        case .media: "photo.stack.fill"
        case .links: "link.circle.fill"
        case .searchResults: "magnifyingglass"
        case .notFound: "questionmark.circle"
        }
    }

    var summary: String {
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }
        if let first = items.first {
            return first.value
        }
        return "Dazu sind noch keine Angaben gespeichert."
    }

    var personID: UUID? {
        personIDs.first
    }
}
