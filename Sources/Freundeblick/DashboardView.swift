import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: LibraryStore

    @Binding var selectedPersonID: UUID?
    @Binding var section: AppSection?
    @Binding var question: String

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                metrics
                peopleSection
                groupSection
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
    }

    private var hero: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Deine Menschen.\nAuf einen Blick.")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Profile, Erinnerungen und Verbindungen – privat auf deinem Mac.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 10) {
                    TextField(
                        "",
                        text: $question,
                        prompt: Text("Was möchtest du wissen?")
                            .foregroundColor(AppTheme.secondaryInk)
                    )
                        .textFieldStyle(.plain)
                        .foregroundColor(AppTheme.ink)
                        .tint(AppTheme.berry)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(.white, in: RoundedRectangle(cornerRadius: 13))
                        .environment(\.colorScheme, .light)
                        .onSubmit { section = .assistant }

                    Button {
                        section = .assistant
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.22))
                }
                .frame(maxWidth: 540)
            }

            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 152, height: 152)
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(28)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.plum.opacity(0.24), radius: 28, y: 16)
    }

    private var metrics: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            MetricCard(
                value: "\(store.data.people.count)",
                title: "Personen",
                systemImage: "person.2.fill",
                tint: AppTheme.plumText
            )
            MetricCard(
                value: "\(mutualFriendshipCount)",
                title: "gegenseitige Verbindungen",
                systemImage: "arrow.left.arrow.right",
                tint: AppTheme.berryText
            )
            MetricCard(
                value: "\(store.inferredGroups.count)",
                title: "mögliche Gruppen",
                systemImage: "circle.hexagongrid.fill",
                tint: AppTheme.coralText
            )
            MetricCard(
                value: "\(store.data.media.count)",
                title: "Erinnerungen",
                systemImage: "photo.stack.fill",
                tint: .orange
            )
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(title: "Menschen", subtitle: "Deine Profile")
                Spacer()
                Button("Alle ansehen") {
                    section = .people
                }
            }

            if store.data.people.isEmpty {
                VStack {
                    EmptyArtwork(
                        systemImage: "person.crop.circle.badge.plus",
                        title: "Noch niemand eingetragen",
                        message: "Lege die erste Person an. Danach kannst du Fakten, Freundschaften und Medien hinzufügen."
                    )
                    Button("Erste Person anlegen") {
                        store.presentNewPersonSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                }
                .frame(maxWidth: .infinity)
                .surfaceCard()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(store.data.people.prefix(8)) { person in
                            PersonCard(person: person) {
                                selectedPersonID = person.id
                                section = .people
                            }
                            .frame(width: 230)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Verbindungen", subtitle: "Automatisch erkannte Muster")

            if store.inferredGroups.isEmpty {
                HStack(spacing: 16) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 34))
                        .foregroundStyle(AppTheme.coralText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gruppen entstehen aus bestätigten Verbindungen")
                            .font(.headline)
                        Text("Wenn sich mindestens drei Personen gegenseitig als Freunde angeben, erscheint hier ein prüfbarer Vorschlag.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Netzwerk öffnen") { section = .network }
                }
                .surfaceCard()
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.inferredGroups) { group in
                        GroupSuggestionCard(group: group) {
                            section = .review
                        }
                    }
                }
            }
        }
    }

    private var mutualFriendshipCount: Int {
        let claims = store.data.relationshipClaims.filter { $0.kind == .friendship }
        var pairs = Set<String>()
        for claim in claims {
            let reverse = claims.contains {
                $0.fromPersonID == claim.toPersonID &&
                $0.toPersonID == claim.fromPersonID
            }
            if reverse {
                let pair = [claim.fromPersonID.uuidString, claim.toPersonID.uuidString].sorted().joined(separator: ":")
                pairs.insert(pair)
            }
        }
        return pairs.count
    }
}

private struct MetricCard: View {
    let value: String
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer()
        }
        .surfaceCard(padding: 15)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }
}

struct PersonCard: View {
    @EnvironmentObject private var store: LibraryStore

    let person: Person
    let action: () -> Void

    private var avatar: MediaItem? {
        guard let id = person.avatarMediaID else { return nil }
        return store.data.media.first { $0.id == id }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                LocalMediaView(media: avatar)
                    .frame(height: 132)
                    .overlay(alignment: .bottomLeading) {
                        if let location = person.location, !location.isEmpty {
                            Label(location, systemImage: "location.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(9)
                        }
                    }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(person.name)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text(ageText(person.birthday))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.berryText)
                    }

                    if !person.temperamentTags.isEmpty {
                        Text(person.temperamentTags.prefix(3).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                            .lineLimit(1)
                    } else {
                        Text("Profil ergänzen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
    }
}

struct GroupSuggestionCard: View {
    @EnvironmentObject private var store: LibraryStore

    let group: Group
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        Circle().fill(AppTheme.coral.opacity(0.14))
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(AppTheme.coralText)
                    }
                    .frame(width: 44, height: 44)
                    Spacer()
                    StatusPill(text: "Vorschlag", systemImage: "sparkles", tint: AppTheme.coralText)
                }

                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)

                Text(memberNames)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard()
        }
        .buttonStyle(.plain)
    }

    private var memberNames: String {
        group.memberIDs.compactMap { id in
            store.data.people.first { $0.id == id }?.name
        }
        .joined(separator: " · ")
    }
}

func ageText(_ birthday: Date?) -> String {
    guard let birthday else { return "Alter offen" }
    let years = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
    return "\(years) J."
}
