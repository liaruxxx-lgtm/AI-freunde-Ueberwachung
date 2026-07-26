import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaGalleryView: View {
    @EnvironmentObject private var store: LibraryStore

    @State private var selectedPersonID: UUID?
    @State private var searchText = ""
    @State private var importError: String?
    @State private var analyzingIDs = Set<UUID>()

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionTitle(title: "Erinnerungen", subtitle: "Fotos und Videos bleiben lokal")
                Spacer()

                Picker("Person", selection: $selectedPersonID) {
                    Text("Alle Personen").tag(UUID?.none)
                    ForEach(store.data.people) { person in
                        Text(person.name).tag(Optional(person.id))
                    }
                }
                .frame(width: 180)

                Button(action: importMedia) {
                    Label("Medien hinzufügen", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
            }
            .padding(24)

            if filteredMedia.isEmpty {
                Spacer()
                EmptyArtwork(
                    systemImage: "photo.on.rectangle.angled",
                    title: "Noch keine Erinnerungen",
                    message: "Importiere Fotos oder Videos und ordne sie einer Person zu. Originale werden in deine lokale Freundeblick-Bibliothek kopiert."
                )
                Button("Fotos oder Videos wählen", action: importMedia)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredMedia) { item in
                            MediaCard(
                                item: item,
                                isAnalyzing: analyzingIDs.contains(item.id),
                                analyze: { analyze(item) }
                            )
                        }
                    }
                    .padding([.horizontal, .bottom], 24)
                }
                .searchable(text: $searchText, prompt: "Tags oder Dateiname")
            }
        }
        .alert("Import nicht möglich", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var filteredMedia: [MediaItem] {
        store.data.media
            .filter { item in
                selectedPersonID.map { item.personIDs.contains($0) } ?? true
            }
            .filter { item in
                guard !searchText.isEmpty else { return true }
                let haystack = ([item.originalFilename] + item.tags + item.clothingTags + item.analysisLabels)
                    .joined(separator: " ")
                return haystack.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.importedAt > $1.importedAt }
    }

    private func importMedia() {
        let panel = NSOpenPanel()
        panel.title = "Fotos und Videos hinzufügen"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie, .video]

        guard panel.runModal() == .OK else { return }
        do {
            let imported = try store.importMedia(
                from: panel.urls,
                personIDs: selectedPersonID.map { [$0] } ?? []
            )
            for item in imported {
                analyze(item)
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func analyze(_ item: MediaItem) {
        guard !analyzingIDs.contains(item.id) else { return }
        analyzingIDs.insert(item.id)
        Task {
            do {
                try await store.analyzeMediaItem(id: item.id)
            } catch {
                importError = error.localizedDescription
            }
            analyzingIDs.remove(item.id)
        }
    }
}

private struct MediaCard: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem
    let isAnalyzing: Bool
    let analyze: () -> Void

    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            LocalMediaView(media: item)
                .frame(height: 160)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 7) {
                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Image(systemName: item.kind == .video ? "video.fill" : "photo.fill")
                            .font(.caption.weight(.bold))
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(9)
                }

            Text(item.originalFilename)
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)

            if !personNames.isEmpty {
                Label(personNames, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.berry)
                    .lineLimit(1)
            }

            if !item.clothingTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.clothingTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.apricot.opacity(0.2), in: Capsule())
                        }
                    }
                }
            } else {
                Text("Noch keine bestätigten Stil-Tags")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !suggestedTags.isEmpty {
                Label("\(suggestedTags.count) lokale Vorschläge", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
            }

            HStack {
                Button("Tags prüfen") {
                    showingEditor = true
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(action: analyze) {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.borderless)
                .disabled(isAnalyzing)
                .help("Lokal neu analysieren")
            }
        }
        .surfaceCard(padding: 12)
        .sheet(isPresented: $showingEditor) {
            MediaEditorView(item: item)
                .environmentObject(store)
        }
    }

    private var personNames: String {
        item.personIDs.compactMap { id in
            store.data.people.first { $0.id == id }?.name
        }
        .joined(separator: ", ")
    }

    private var suggestedTags: [String] {
        item.analysisLabels.compactMap { label in
            let prefix = "Kleidungsvorschlag: "
            return label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : nil
        }
    }
}

private struct MediaEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let item: MediaItem

    @State private var tags: [String]
    @State private var clothingTags: [String]
    @State private var notes: String
    @State private var selectedPeople: Set<UUID>
    @State private var errorMessage: String?

    init(item: MediaItem) {
        self.item = item
        _tags = State(initialValue: item.tags)
        _clothingTags = State(initialValue: item.clothingTags)
        _notes = State(initialValue: item.notes)
        _selectedPeople = State(initialValue: Set(item.personIDs))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Medien-Tags prüfen")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Bestätigen", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
            }
            .padding(20)
            Divider()

            Form {
                Section("Zugeordnete Personen") {
                    ForEach(store.data.people) { person in
                        Toggle(
                            person.name,
                            isOn: Binding(
                                get: { selectedPeople.contains(person.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedPeople.insert(person.id)
                                    } else {
                                        selectedPeople.remove(person.id)
                                    }
                                }
                            )
                        )
                    }
                }

                Section("Lokale Kleidungsvorschläge") {
                    if suggestedTags.isEmpty {
                        Text("Keine Kleidung sicher genug erkannt.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestedTags, id: \.self) { suggestion in
                            Toggle(
                                suggestion,
                                isOn: Binding(
                                    get: { clothingTags.contains(suggestion) },
                                    set: { enabled in
                                        if enabled {
                                            if !clothingTags.contains(suggestion) {
                                                clothingTags.append(suggestion)
                                            }
                                        } else {
                                            clothingTags.removeAll { $0 == suggestion }
                                        }
                                    }
                                )
                            )
                        }
                    }
                    Text("Erst deine Auswahl wird als bestätigter Stil-Tag gespeichert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Eigene Angaben") {
                    TokenSuggestionField(
                        title: "Medien-Tags",
                        placeholder: "Tag eingeben, z. B. „Ur“",
                        suggestions: ProfileSuggestionCatalog.mediaTags
                            + store.data.media.flatMap(\.tags),
                        tint: AppTheme.berry,
                        values: $tags
                    )
                    TextField("Notiz", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 620)
        .alert("Speichern nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var suggestedTags: [String] {
        item.analysisLabels.compactMap { label in
            let prefix = "Kleidungsvorschlag: "
            return label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : nil
        }
    }

    private func save() {
        var updated = item
        updated.personIDs = Array(selectedPeople)
        updated.tags = tags
        updated.clothingTags = Array(Set(clothingTags)).sorted()
        updated.notes = notes

        do {
            try store.updateMedia(updated)
            try store.refreshConfirmedClothingPatterns(for: updated.personIDs)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
