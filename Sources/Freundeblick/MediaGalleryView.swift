import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum MediaGalleryFilter: String, CaseIterable, Identifiable {
    case all
    case images
    case videos
    case missing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .images: "Fotos"
        case .videos: "Videos"
        case .missing: "Fehlend"
        }
    }
}

private struct MediaDeletionDialogModifier: ViewModifier {
    @EnvironmentObject private var store: LibraryStore

    let item: MediaItem
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    let onDeleted: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "„\(item.originalFilename)“ löschen?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Aus Freundeblick entfernen", role: .destructive) {
                delete(deleteStoredFile: false)
            }

            if !isFileMissing {
                Button("Auch lokale Kopie löschen", role: .destructive) {
                    delete(deleteStoredFile: true)
                }
            }

            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(deletionMessage)
        }
    }

    private var isFileMissing: Bool {
        !FileManager.default.fileExists(
            atPath: store.mediaURL(for: item).path
        )
    }

    private var deletionMessage: String {
        var consequences = [
            "Der Medieneintrag wird aus Freundeblick entfernt.",
        ]

        if !avatarPersonNames.isEmpty {
            consequences.append(
                "Das Profilbild von \(avatarPersonNames.joined(separator: ", ")) wird entfernt."
            )
        }

        if evidenceCount > 0 {
            consequences.append(
                evidenceCount == 1
                    ? "Die Verknüpfung zu einer Beobachtung wird gelöst."
                    : "Die Verknüpfungen zu \(evidenceCount) Beobachtungen werden gelöst."
            )
        }

        if isFileMissing {
            consequences.append("Die lokale Datei fehlt bereits.")
        } else {
            consequences.append(
                "Mit „Auch lokale Kopie löschen“ wird nur Freundeblicks Kopie entfernt. "
                    + "Die ursprüngliche Datei außerhalb von Freundeblick bleibt unverändert."
            )
        }

        return consequences.joined(separator: " ")
    }

    private var avatarPersonNames: [String] {
        store.data.people
            .filter { $0.avatarMediaID == item.id }
            .map(\.name)
            .sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
    }

    private var evidenceCount: Int {
        store.data.observations.count {
            $0.evidenceMediaIDs.contains(item.id)
        }
    }

    private func delete(deleteStoredFile: Bool) {
        do {
            try store.deleteMedia(
                id: item.id,
                deleteStoredFile: deleteStoredFile,
                expecting: item
            )
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func mediaDeletionDialog(
        item: MediaItem,
        isPresented: Binding<Bool>,
        errorMessage: Binding<String?>,
        onDeleted: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            MediaDeletionDialogModifier(
                item: item,
                isPresented: isPresented,
                errorMessage: errorMessage,
                onDeleted: onDeleted
            )
        )
    }
}

struct MediaGalleryView: View {
    @EnvironmentObject private var store: LibraryStore

    @State private var selectedPersonID: UUID?
    @State private var selectedFilter: MediaGalleryFilter = .all
    @State private var searchText = ""
    @State private var importError: String?
    @State private var analyzingIDs = Set<UUID>()

    private let columns = [
        GridItem(
            .adaptive(minimum: 280, maximum: 360),
            spacing: 22,
            alignment: .top
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(
                        title: "Medien",
                        subtitle: "Fotos und Videos sicher und lokal verwalten"
                    )
                    Spacer()

                    Button(action: importMedia) {
                        Label(importButtonTitle, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                    .help(importButtonHelp)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        mediaSummary
                        Spacer(minLength: 8)
                        mediaFilters
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        mediaSummary
                        mediaFilters
                    }
                }
            }
            .padding(24)

            if store.data.media.isEmpty {
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
            } else if filteredMedia.isEmpty {
                Spacer()
                EmptyArtwork(
                    systemImage: "magnifyingglass",
                    title: "Keine passenden Medien",
                    message: "Ändere den Suchtext oder zeige wieder die Medien aller Personen."
                )
                Button("Filter zurücksetzen") {
                    searchText = ""
                    selectedPersonID = nil
                    selectedFilter = .all
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: columns,
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(filteredMedia) { item in
                            MediaCard(
                                item: item,
                                isAnalyzing: analyzingIDs.contains(item.id),
                                analyze: { analyze(item) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom], 24)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Tags, Person oder Dateiname")
        .background {
            MediaTabBackground()
                .ignoresSafeArea()
        }
        .alert("Medienaktion nicht möglich", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var mediaSummary: some View {
        HStack(spacing: 8) {
            MediaSummaryPill(
                value: store.data.media.count,
                label: "Medien",
                systemImage: "photo.stack.fill",
                tint: AppTheme.plumText
            )
            MediaSummaryPill(
                value: imageCount,
                label: "Fotos",
                systemImage: "photo.fill",
                tint: AppTheme.berryText
            )
            MediaSummaryPill(
                value: videoCount,
                label: "Videos",
                systemImage: "video.fill",
                tint: AppTheme.coralText
            )
            if missingCount > 0 {
                MediaSummaryPill(
                    value: missingCount,
                    label: "fehlen",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: AppTheme.coralText
                )
            }
        }
    }

    private var mediaFilters: some View {
        HStack(spacing: 12) {
            Picker("Medientyp", selection: $selectedFilter) {
                ForEach(MediaGalleryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 310)
            .accessibilityLabel("Medientyp")

            Picker("Person", selection: $selectedPersonID) {
                Text("Alle Personen").tag(UUID?.none)
                ForEach(sortedPeople) { person in
                    Text(mediaPersonLabel(person, among: sortedPeople))
                        .tag(Optional(person.id))
                }
            }
            .frame(width: 180)
        }
    }

    private var filteredMedia: [MediaItem] {
        store.data.media
            .filter { item in
                selectedPersonID.map { item.personIDs.contains($0) } ?? true
            }
            .filter(matchesSelectedFilter)
            .filter { item in
                guard !searchText.isEmpty else { return true }
                let personNames = item.personIDs.compactMap { id in
                    store.person(id: id)?.name
                }
                let haystack = (
                    [item.originalFilename]
                        + item.tags
                        + item.clothingTags
                        + item.analysisLabels
                        + personNames
                )
                    .joined(separator: " ")
                return haystack.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.importedAt > $1.importedAt }
    }

    private var sortedPeople: [Person] {
        store.data.people.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var imageCount: Int {
        store.data.media.count { $0.kind == .image }
    }

    private var videoCount: Int {
        store.data.media.count { $0.kind == .video }
    }

    private var missingCount: Int {
        store.data.media.count(where: isFileMissing)
    }

    private func matchesSelectedFilter(_ item: MediaItem) -> Bool {
        switch selectedFilter {
        case .all:
            true
        case .images:
            item.kind == .image
        case .videos:
            item.kind == .video
        case .missing:
            isFileMissing(item)
        }
    }

    private func isFileMissing(_ item: MediaItem) -> Bool {
        !FileManager.default.fileExists(
            atPath: store.mediaURL(for: item).path
        )
    }

    private var selectedPersonLabel: String? {
        guard let selectedPersonID else { return nil }
        guard let person = store.person(id: selectedPersonID) else {
            return nil
        }
        return mediaPersonLabel(person, among: sortedPeople)
    }

    private var importButtonTitle: String {
        selectedPersonLabel.map { "Für \($0) hinzufügen" }
            ?? "Medien hinzufügen"
    }

    private var importButtonHelp: String {
        selectedPersonLabel.map {
            "Neue Medien werden direkt \($0) zugeordnet."
        } ?? "Neue Medien werden zunächst keiner Person zugeordnet."
    }

    private func importMedia() {
        let panel = NSOpenPanel()
        panel.title = selectedPersonLabel.map {
            "Fotos und Videos für \($0) hinzufügen"
        } ?? "Fotos und Videos hinzufügen"
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

private struct MediaSummaryPill: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text("\(value) \(label)")
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: Capsule())
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct MediaTabBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.canvas(for: colorScheme)

            LinearGradient(
                colors: [
                    AppTheme.plum.opacity(0.10),
                    AppTheme.berry.opacity(0.07),
                    AppTheme.apricot.opacity(0.11),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.coral.opacity(0.11))
                .frame(width: 430, height: 430)
                .blur(radius: 75)
                .offset(x: 360, y: -250)

            Circle()
                .fill(AppTheme.plum.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: -340, y: 280)
        }
        .accessibilityHidden(true)
    }
}

private struct MediaCard: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.colorScheme) private var colorScheme

    let item: MediaItem
    let isAnalyzing: Bool
    let analyze: () -> Void

    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var deletionError: String?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: openMedia) {
                GeometryReader { geometry in
                    LocalMediaView(media: item)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                }
                    .frame(maxWidth: .infinity)
                    .frame(height: 184)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay(alignment: .topLeading) {
                        if isFileMissing {
                            Label("Datei fehlt", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.black.opacity(0.86))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(AppTheme.apricot, in: Capsule())
                                .padding(10)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 7) {
                            if isAnalyzing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Image(
                                systemName: item.kind == .video
                                    ? "video.fill"
                                    : "photo.fill"
                            )
                            .font(.caption.weight(.bold))
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(9)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .disabled(isFileMissing)
            .accessibilityLabel("Medium öffnen: \(item.originalFilename)")
            .help(
                isFileMissing
                    ? "Die lokale Datei fehlt. Öffne „Bearbeiten“, um sie wiederzufinden."
                    : "Medium öffnen"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.originalFilename)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.originalFilename)

                Label(
                    displayDate,
                    systemImage: item.kind == .video ? "video.fill" : "photo.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !personNames.isEmpty {
                Label(personNames, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.berryText)
                    .lineLimit(1)
                    .help(personNames)
            }

            if !visibleTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(visibleTags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 220, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.apricot.opacity(0.18), in: Capsule())
                            .help(tag)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            } else {
                Text("Noch keine Tags")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !suggestedTags.isEmpty {
                Label("\(suggestedTags.count) lokale Vorschläge", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.coralText)
            }

            mediaActions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isHovered
                        ? AppTheme.berry.opacity(colorScheme == .dark ? 0.55 : 0.34)
                        : Color.primary.opacity(0.09),
                    lineWidth: isHovered ? 1.5 : 1
                )
        }
        .shadow(
            color: AppTheme.plum.opacity(isHovered ? 0.16 : 0.08),
            radius: isHovered ? 12 : 8,
            y: isHovered ? 5 : 3
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .sheet(isPresented: $showingEditor) {
            MediaEditorView(item: item)
                .environmentObject(store)
        }
        .mediaDeletionDialog(
            item: item,
            isPresented: $showingDeleteConfirmation,
            errorMessage: $deletionError
        )
        .alert("Löschen nicht möglich", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }

    private var mediaActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                editMediaButton
                openMediaButton
                Spacer(minLength: 0)
                analyzeMediaButton
                deleteMediaButton
            }

            VStack(spacing: 8) {
                editMediaButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    openMediaButton
                    Spacer(minLength: 0)
                    analyzeMediaButton
                    deleteMediaButton
                }
            }
        }
    }

    private var editMediaButton: some View {
        Button {
            showingEditor = true
        } label: {
            Label("Bearbeiten", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
    }

    private var openMediaButton: some View {
        Button(action: openMedia) {
            Label("Öffnen", systemImage: "arrow.up.right.square")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .disabled(isFileMissing)
        .help(isFileMissing ? "Die lokale Datei fehlt" : "Medium öffnen")
    }

    private var analyzeMediaButton: some View {
        Button(action: analyze) {
            Label("Neu analysieren", systemImage: "sparkles")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .disabled(isAnalyzing)
        .help("Lokal neu analysieren")
    }

    private var deleteMediaButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("Medium löschen", systemImage: "trash")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(AppTheme.coralText)
        .disabled(isAnalyzing)
        .help(
            isAnalyzing
                ? "Bitte warte, bis die Analyse abgeschlossen ist"
                : "Medium löschen"
        )
    }

    private var personNames: String {
        item.personIDs.compactMap { id in
            guard let person = store.data.people.first(where: { $0.id == id }) else {
                return nil
            }
            return mediaPersonLabel(person, among: store.data.people)
        }
        .joined(separator: ", ")
    }

    private var isFileMissing: Bool {
        !FileManager.default.fileExists(
            atPath: store.mediaURL(for: item).path
        )
    }

    private func openMedia() {
        guard !isFileMissing else { return }
        NSWorkspace.shared.open(store.mediaURL(for: item))
    }

    private var displayDate: String {
        let date = item.capturedAt ?? item.importedAt
        let prefix = item.capturedAt == nil ? "Importiert" : "Aufgenommen"
        return "\(prefix) \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private var visibleTags: [String] {
        var seen = Set<String>()
        return (item.tags + item.clothingTags)
            .filter { seen.insert($0.localizedLowercase).inserted }
            .prefix(3)
            .map(\.self)
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
    @State private var showingDeleteConfirmation = false
    @State private var showingDiscardConfirmation = false

    init(item: MediaItem) {
        self.item = item
        _tags = State(initialValue: item.tags)
        _clothingTags = State(initialValue: item.clothingTags)
        _notes = State(initialValue: item.notes)
        _selectedPeople = State(initialValue: Set(item.personIDs))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Medium bearbeiten")
                        .font(.title2.weight(.bold))
                    Text(item.originalFilename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Abbrechen", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Speichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    LocalMediaView(media: item)
                        .frame(height: 190)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        }

                    if isFileMissing {
                        Label(
                            "Lokale Datei fehlt",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.coralText)
                    }

                    Text(item.originalFilename)
                        .font(.callout.weight(.bold))
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Label(
                        item.kind == .video ? "Video" : "Foto",
                        systemImage: item.kind == .video ? "video.fill" : "photo.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Label(
                        "Importiert \(item.importedAt.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if isFileMissing {
                        Button(action: requestRestoreMissingFile) {
                            Label(
                                "Datei wiederfinden",
                                systemImage: "folder.badge.questionmark"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Medium löschen", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(AppTheme.coralText)
                }
                .padding(20)
                .frame(width: 260)
                .background(Color.primary.opacity(0.025))

                Divider()

                Form {
                    Section("Zugeordnete Personen") {
                        ForEach(sortedPeople) { person in
                            Toggle(
                                mediaPersonLabel(person, among: sortedPeople),
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
                        Button("Von allen Personen lösen") {
                            selectedPeople.removeAll()
                        }
                        .disabled(selectedPeople.isEmpty)
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
                            tint: AppTheme.berryText,
                            values: $tags
                        )
                        TextField("Notiz", text: $notes, axis: .vertical)
                            .lineLimit(3...7)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 800, height: 660)
        .alert("Aktion nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .mediaDeletionDialog(
            item: item,
            isPresented: $showingDeleteConfirmation,
            errorMessage: $errorMessage,
            onDeleted: { dismiss() }
        )
        .confirmationDialog(
            "Ungespeicherte Änderungen verwerfen?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Änderungen verwerfen", role: .destructive) {
                dismiss()
            }
            Button("Weiter bearbeiten", role: .cancel) {}
        } message: {
            Text("Deine Änderungen an Personen, Tags oder Notiz wurden noch nicht gespeichert.")
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    private var suggestedTags: [String] {
        item.analysisLabels.compactMap { label in
            let prefix = "Kleidungsvorschlag: "
            return label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : nil
        }
    }

    private var isFileMissing: Bool {
        !FileManager.default.fileExists(
            atPath: store.mediaURL(for: item).path
        )
    }

    private var sortedPeople: [Person] {
        store.data.people.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var hasUnsavedChanges: Bool {
        tags != item.tags
            || Array(Set(clothingTags)).sorted()
                != Array(Set(item.clothingTags)).sorted()
            || notes != item.notes
            || selectedPeople != Set(item.personIDs)
    }

    private func save() {
        var updated = item
        updated.personIDs = Array(selectedPeople)
        updated.tags = tags
        updated.clothingTags = Array(Set(clothingTags)).sorted()
        updated.notes = notes

        do {
            try store.updateMediaAndRefreshPatterns(
                updated,
                expecting: item
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() {
        if hasUnsavedChanges {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func requestRestoreMissingFile() {
        guard !hasUnsavedChanges else {
            errorMessage = "Speichere zuerst deine Änderungen an Personen, Tags oder Notiz. "
                + "Öffne das Medium danach erneut, um die fehlende Datei wiederzufinden."
            return
        }
        restoreMissingFile()
    }

    private func restoreMissingFile() {
        let panel = NSOpenPanel()
        panel.title = "Passende Mediendatei wiederfinden"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = item.kind == .image
            ? [.image]
            : [.movie, .video]

        guard panel.runModal() == .OK,
              let sourceURL = panel.url
        else {
            return
        }

        do {
            try store.restoreMissingMediaFile(
                id: item.id,
                from: sourceURL,
                expecting: item
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func mediaPersonLabel(
    _ person: Person,
    among people: [Person]
) -> String {
    let normalizedName = person.name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .localizedLowercase
    let matchingPeople = people.filter {
        $0.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase == normalizedName
    }

    guard matchingPeople.count > 1 else {
        return person.name
    }

    if let location = uniqueMediaPersonDetail(
        person.location,
        for: person,
        among: matchingPeople,
        value: \.location
    ) {
        return "\(person.name) · Ort: \(location)"
    }

    if let alias = person.aliases.first(where: {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
        let normalizedAlias = alias
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        let aliasIsUnique = matchingPeople
            .filter { $0.id != person.id }
            .allSatisfy { other in
                !other.aliases.contains {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .localizedLowercase == normalizedAlias
                }
        }
        if aliasIsUnique {
            return "\(person.name) · Alias: \(alias)"
        }
    }

    return "\(person.name) · Profil \(person.id.uuidString.prefix(6))"
}

private func uniqueMediaPersonDetail(
    _ detail: String?,
    for person: Person,
    among matchingPeople: [Person],
    value: (Person) -> String?
) -> String? {
    guard let trimmed = detail?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !trimmed.isEmpty
    else {
        return nil
    }

    let normalized = trimmed.localizedLowercase
    let isUnique = matchingPeople
        .filter { $0.id != person.id }
        .allSatisfy { other in
            value(other)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedLowercase != normalized
        }
    return isUnique ? trimmed : nil
}
