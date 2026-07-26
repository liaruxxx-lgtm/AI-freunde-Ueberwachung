import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case people
    case compare
    case network
    case media
    case review
    case assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .people: "Personen"
        case .compare: "Vergleichen"
        case .network: "Netzwerk"
        case .media: "Medien"
        case .review: "Prüfen"
        case .assistant: "Codex-Zugriff"
        }
    }

    var icon: String {
        switch self {
        case .overview: "sparkles.rectangle.stack"
        case .people: "person.2.fill"
        case .compare: "chart.bar.xaxis"
        case .network: "point.3.connected.trianglepath.dotted"
        case .media: "photo.on.rectangle.angled"
        case .review: "checkmark.seal"
        case .assistant: "bolt.horizontal.circle"
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selection: AppSection?
    @Binding var selectedPersonID: UUID?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }

            if !store.data.people.isEmpty {
                Section("Schnellzugriff") {
                    ForEach(store.data.people.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { person in
                        Button {
                            selectedPersonID = person.id
                            selection = .people
                        } label: {
                            Label(person.name, systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Freundeblick")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(AppTheme.plum)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lokal gespeichert")
                        .font(.caption.weight(.semibold))
                    Text("Keine Cloud nötig")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.thinMaterial)
        }
    }
}
