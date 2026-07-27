import AppKit
import SwiftUI
import WebKit

private enum WebResearchMode: String, CaseIterable, Identifiable {
    case clues
    case person

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clues: "Hinweise kombinieren"
        case .person: "Person gezielt suchen"
        }
    }
}

struct WebResearchView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let person: Person

    @State private var researchMode: WebResearchMode = .clues
    @State private var selectedClues = Set<String>()
    @State private var customClue = ""
    @State private var includeClueLocation = true
    @State private var contextResults: [PublicWebResult] = []
    @State private var isContextSearching = false
    @State private var hasContextSearched = false
    @State private var contextError: String?
    @State private var importCandidate: PublicWebResult?
    @State private var additionalTerms = ""
    @State private var includeLocation = false
    @State private var confirmedAdultForSearch = false
    @State private var wikipediaResults: [PublicKnowledgeResult] = []
    @State private var webSearchURL: URL?
    @State private var webSearchID = UUID()
    @State private var selectedPage: SelectedPublicPage?
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var knowledgeError: String?
    @State private var browserMessage: String?
    @State private var saveMessage: String?

    private let researchService = PublicWebResearchService()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Picker("Rechercheart", selection: $researchMode) {
                    ForEach(WebResearchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if researchMode == .clues {
                    cluePrivacyNotice
                    clueResearchContent
                } else {
                    privacyNotice
                    searchControls

                    HSplitView {
                        knowledgeColumn
                            .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)

                        webSearchColumn
                            .frame(minWidth: 500, maxWidth: .infinity)
                    }
                }
            }
            .padding(18)
        }
        .frame(minWidth: 920, idealWidth: 1_050, minHeight: 720, idealHeight: 800)
        .onAppear(perform: selectInitialClues)
        .sheet(item: $importCandidate) { candidate in
            ResearchCandidateImportSheet(
                candidate: candidate,
                onSave: { value, detailKey, saveSource in
                    importConfirmedFact(
                        candidate: candidate,
                        value: value,
                        detailKey: detailKey,
                        saveSource: saveSource
                    )
                }
            )
        }
        .alert("Link konnte nicht gespeichert werden", isPresented: Binding(
            get: { saveMessage?.hasPrefix("Fehler:") == true },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveMessage = nil }
        } message: {
            Text(saveMessage?.replacingOccurrences(of: "Fehler: ", with: "") ?? "")
        }
    }

    private var cluePrivacyNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title3)
                .foregroundStyle(AppTheme.plumText)

            VStack(alignment: .leading, spacing: 5) {
                Text("Hinweise ergeben Suchwege – noch keine Tatsachen")
                    .font(.callout.weight(.semibold))
                Text(
                    "Freundeblick kombiniert nur die unten ausgewählten Angaben. "
                        + "Der Name wird in diesem Schritt nicht gesendet. Die sichtbaren "
                        + "Suchtexte gehen erst mit „Hinweise durchsuchen“ an DuckDuckGo; "
                        + "der Dienst erhält dabei technisch deine IP-Adresse."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(
                    "Ein passender Verein ist nur eine Möglichkeit, kein Beweis für eine "
                        + "Mitgliedschaft. Erst du prüfst die Quelle, bearbeitest die Angabe "
                        + "und übernimmst sie bewusst in den Steckbrief."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 14)
    }

    private var clueResearchContent: some View {
        HSplitView {
            clueControls
                .frame(minWidth: 310, idealWidth: 350, maxWidth: 410)

            clueResults
                .frame(minWidth: 510, maxWidth: .infinity)
        }
    }

    private var clueControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionTitle(
                title: "1. Hinweise auswählen",
                subtitle: "Maximal drei Themen werden gleichzeitig gesucht"
            )

            if clueOptions.isEmpty {
                Text("Im Steckbrief sind noch keine Interessen oder Sportarten gespeichert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(clueOptions, id: \.self) { clue in
                            Button {
                                toggleClue(clue)
                            } label: {
                                Label(
                                    clue,
                                    systemImage: selectedClues.contains(clue)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedClues.contains(clue) ? AppTheme.berry : .secondary)
                        }
                    }
                }
            }

            TextField("Weiterer Hinweis, z. B. Badminton", text: $customClue)
                .textFieldStyle(.roundedBorder)

            if let location = cleanLocation {
                Toggle("Ort „\(location)“ kombinieren", isOn: $includeClueLocation)
                    .toggleStyle(.checkbox)
            }

            Divider()

            Text("Diese Suchtexte werden gesendet:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(contextQueries) { query in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(query.clue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.berryText)
                            Text(query.text)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surfaceCard(padding: 9)
                    }
                }
            }

            if contextQueries.isEmpty {
                Label(
                    "Wähle ein Thema oder schreibe einen Hinweis.",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: startContextSearch) {
                if isContextSearching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Hinweise durchsuchen", systemImage: "sparkle.magnifyingglass")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.berry)
            .disabled(contextQueries.isEmpty || isContextSearching)
        }
        .padding(14)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }

    private var clueResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                title: "2. Mögliche Quellen prüfen",
                subtitle: "Webseiten und öffentliche Social-Media-Treffer, nach Quelle zusammengeführt"
            )

            if isContextSearching && contextResults.isEmpty {
                Spacer()
                ProgressView("Öffentliche Quellen werden gesammelt …")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if let contextError {
                Spacer()
                EmptyArtwork(
                    systemImage: "wifi.exclamationmark",
                    title: "Suche nicht erreichbar",
                    message: contextError
                )
                Spacer()
            } else if contextResults.isEmpty && !hasContextSearched {
                Spacer()
                EmptyArtwork(
                    systemImage: "point.3.filled.connected.trianglepath.dotted",
                    title: "Noch keine Hinweis-Suche",
                    message: "Beispiel: „Badminton“ und „Schneverdingen“ können zu möglichen Vereinen, Trainingsseiten und öffentlichen Social-Media-Seiten führen."
                )
                Spacer()
            } else if contextResults.isEmpty {
                Spacer()
                EmptyArtwork(
                    systemImage: "magnifyingglass",
                    title: "Keine passenden Quellen gefunden",
                    message: "Versuche einen genaueren Sport-, Vereins- oder Ortsbegriff. Das Ergebnis sagt nichts darüber aus, ob die Person dort Mitglied ist."
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(contextResults) { result in
                            contextResultCard(result)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 17))

            VStack(alignment: .leading, spacing: 2) {
                Text("Öffentliche Web-Recherche")
                    .font(.title2.weight(.bold))
                Text("Mögliche Quellen für \(person.name) finden und selbst zuordnen")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Button("Schließen") { dismiss() }
        }
        .padding(20)
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.plumText)

            VStack(alignment: .leading, spacing: 5) {
                Text("Du entscheidest, was das Gerät verlässt")
                    .font(.callout.weight(.semibold))
                Text(
                    "Erst mit „Suche starten“ wird der vollständig sichtbare Suchtext "
                        + "an Wikipedia und DuckDuckGo gesendet. Beide Dienste erhalten "
                        + "dabei technisch deine IP-Adresse. Automatisch ergänzt werden "
                        + "nur der Name und – wenn aktiviert – der gespeicherte Ortswert. "
                        + "Alles im Feld „Suchzusatz“ wird ebenfalls gesendet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(
                    "Namensgleiche Personen sind nur mögliche Treffer. Freundeblick "
                        + "übernimmt keine Fakten automatisch und blockiert bekannte "
                        + "direkte Links zu einigen Personensuchdiensten. Vollständig "
                        + "klassifizieren lassen sich Treffer und Weiterleitungen nicht."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 14)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField(
                    "Suchzusatz, z. B. Benutzername, Verein oder Beruf",
                    text: $additionalTerms
                )
                .textFieldStyle(.roundedBorder)

                if person.location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Toggle("Gespeicherten Ort mitsenden", isOn: $includeLocation)
                        .toggleStyle(.checkbox)
                }

                Button(action: startSearch) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Suche starten", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
                .disabled(!canStartSearch || isSearching)
            }

            if person.age() == nil {
                Toggle(
                    "Ich bestätige, dass \(person.name) mindestens 18 Jahre alt ist.",
                    isOn: $confirmedAdultForSearch
                )
                .toggleStyle(.checkbox)
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Gesendet wird:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(searchQuery)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let restrictionMessage {
                Label(restrictionMessage, systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.coralText)
            }
        }
    }

    private var knowledgeColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                title: "Strukturierte Kurzinfos",
                subtitle: "Offizielle Wikipedia-Suche"
            )

            if isSearching && wikipediaResults.isEmpty {
                Spacer()
                ProgressView("Wikipedia wird geprüft …")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if let knowledgeError {
                Spacer()
                EmptyArtwork(
                    systemImage: "wifi.exclamationmark",
                    title: "Wikipedia nicht erreichbar",
                    message: knowledgeError
                )
                Spacer()
            } else if wikipediaResults.isEmpty && !hasSearched {
                Spacer()
                EmptyArtwork(
                    systemImage: "text.book.closed.fill",
                    title: "Noch keine Suche",
                    message: "Bei bekannten Personen erscheinen hier Quellen mit kurzer Vorschau."
                )
                Spacer()
            } else if wikipediaResults.isEmpty {
                Spacer()
                EmptyArtwork(
                    systemImage: "magnifyingglass",
                    title: "Keine Wikipedia-Treffer",
                    message: "Das bedeutet nicht, dass es keine öffentlichen Seiten gibt. Prüfe die allgemeine Suche rechts und ordne nichts nur anhand des Namens zu."
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(wikipediaResults) { result in
                            knowledgeResultCard(result)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }

    private var webSearchColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(
                    title: "Allgemeine Websuche",
                    subtitle: "DuckDuckGo · keine dauerhaften Cookies in Freundeblick"
                )
                Spacer()
                StatusPill(text: "JavaScript aus", systemImage: "lock.fill", tint: .green)
            }

            PrivateSearchWebView(
                searchURL: webSearchURL,
                searchID: webSearchID,
                selectedPage: $selectedPage,
                message: $browserMessage
            )
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.secondary.opacity(0.18))
            }

            if let selectedPage {
                selectedPageBar(selectedPage)
            } else if let browserMessage {
                Label(browserMessage, systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.coralText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(padding: 10)
            } else {
                Text(
                    "Wähle auf der DuckDuckGo-Seite einen Treffer. Freundeblick hält "
                        + "vor dem Öffnen an, damit du URL und Quelle prüfen kannst. "
                        + "Das macht die Suche nicht anonym; im Standardbrowser gelten "
                        + "dessen Verlauf, Cookies und die Regeln der Zielseite."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }

    private func contextResultCard(_ result: PublicWebResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: socialIcon(for: result.url))
                    .foregroundStyle(AppTheme.berryText)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.callout.weight(.semibold))
                    Text(result.hostLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Möglicher Treffer")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.plumText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.plum.opacity(0.1), in: Capsule())
            }

            Text(result.excerpt)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
                .lineLimit(4)

            Label(
                "Passt zur Suche nach \(result.matchedClues.joined(separator: ", ")) – keine bestätigte Verbindung.",
                systemImage: "exclamationmark.bubble.fill"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Button("Quelle öffnen") {
                    openURL(result.url)
                }
                .buttonStyle(.borderless)

                Button("Mit Personennamen prüfen") {
                    preparePersonCheck(result)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Angabe übernehmen") {
                    importCandidate = result
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
            }
        }
        .surfaceCard(padding: 12)
    }

    private func knowledgeResultCard(_ result: PublicKnowledgeResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(systemName: "text.book.closed.fill")
                    .foregroundStyle(AppTheme.berryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.callout.weight(.semibold))
                    Text(result.hostLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(result.excerpt)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
                .lineLimit(5)

            HStack {
                Button("Quelle öffnen") {
                    openURL(result.url)
                }
                .buttonStyle(.borderless)

                Spacer()

                if isSaved(result.url) {
                    Label("Gespeichert", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button("Gehört zu \(person.name) – speichern") {
                        save(
                            url: result.url,
                            title: result.title
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .surfaceCard(padding: 12)
    }

    private func selectedPageBar(_ page: SelectedPublicPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(AppTheme.berryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Treffer ausgewählt: \(page.host)")
                        .font(.callout.weight(.semibold))
                    Text(page.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            HStack {
                Button("Im Browser prüfen") {
                    openURL(page.url)
                }
                Spacer()
                if isSaved(page.url) {
                    Label("Gespeichert", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button("Gehört zu \(person.name) – speichern") {
                        save(url: page.url, title: page.host)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                }
            }
        }
        .surfaceCard(padding: 11)
    }

    private var searchQuery: String {
        PublicWebResearchService.searchQuery(
            person: person,
            includeLocation: includeLocation,
            additionalTerms: additionalTerms
        )
    }

    private var cleanLocation: String? {
        guard let location = person.location?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty
        else {
            return nil
        }
        return location
    }

    private var clueOptions: [String] {
        ContextResearchPlanner.uniqueCleanValues(
            person.interests + (person.profileDetails["favoriteSports"] ?? [])
        )
    }

    private var selectedContextClues: [String] {
        var values: [String] = []
        let custom = customClue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            values.append(custom)
        }
        values.append(contentsOf: clueOptions.filter(selectedClues.contains))
        return ContextResearchPlanner.uniqueCleanValues(values)
    }

    private var contextQueries: [ContextResearchQuery] {
        ContextResearchPlanner.queries(
            location: includeClueLocation ? cleanLocation : nil,
            clues: selectedContextClues
        )
    }

    private var isKnownMinor: Bool {
        person.age().map { $0 < 18 } ?? false
    }

    private var adultStatusAllowsSearch: Bool {
        if let age = person.age() {
            return age >= 18
        }
        return confirmedAdultForSearch
    }

    private var hasEnoughIdentityContext: Bool {
        let nameParts = person.name.split(whereSeparator: \.isWhitespace)
        return nameParts.count >= 2
            || !additionalTerms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canStartSearch: Bool {
        adultStatusAllowsSearch && hasEnoughIdentityContext && searchQuery.count <= 240
    }

    private var restrictionMessage: String? {
        if isKnownMinor {
            return "Für Minderjährige ist die automatische Namenssuche deaktiviert. Du kannst bekannte Links weiterhin manuell eintragen."
        }
        if person.age() == nil && !confirmedAdultForSearch {
            return "Ohne bekannten Geburtstag startet die Suche erst nach deiner Bestätigung der Volljährigkeit."
        }
        if !hasEnoughIdentityContext {
            return "Ein Vorname allein ist zu ungenau. Ergänze z. B. einen bestätigten Benutzernamen, Verein oder Beruf."
        }
        if searchQuery.count > 240 {
            return "Der Suchtext ist zu lang. Kürze den Suchzusatz auf wenige eindeutige Begriffe."
        }
        return nil
    }

    private func startSearch() {
        guard canStartSearch else { return }
        knowledgeError = nil
        browserMessage = nil
        selectedPage = nil
        wikipediaResults = []
        hasSearched = true
        webSearchURL = PublicWebResearchService.duckDuckGoSearchURL(query: searchQuery)
        webSearchID = UUID()
        isSearching = true

        Task {
            do {
                wikipediaResults = try await researchService.searchWikipedia(query: searchQuery)
            } catch {
                knowledgeError = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func selectInitialClues() {
        guard selectedClues.isEmpty else { return }
        selectedClues = Set(clueOptions.prefix(3))
    }

    private func toggleClue(_ clue: String) {
        if selectedClues.contains(clue) {
            selectedClues.remove(clue)
        } else if selectedClues.count < 3 {
            selectedClues.insert(clue)
        }
    }

    private func startContextSearch() {
        let queries = contextQueries
        guard !queries.isEmpty else { return }
        contextError = nil
        contextResults = []
        hasContextSearched = true
        isContextSearching = true

        Task {
            do {
                contextResults = try await researchService.searchPublicWeb(
                    queries: queries
                )
            } catch {
                contextError = error.localizedDescription
            }
            isContextSearching = false
        }
    }

    private func preparePersonCheck(_ result: PublicWebResult) {
        let compactTitle = result.title
            .replacingOccurrences(of: "\"", with: "")
            .prefix(100)
        additionalTerms = "\"\(compactTitle)\""
        includeLocation = cleanLocation != nil
        researchMode = .person
    }

    private func importConfirmedFact(
        candidate: PublicWebResult,
        value: String,
        detailKey: String,
        saveSource: Bool
    ) {
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanValue.isEmpty else { return }
        guard var current = store.person(id: person.id) else {
            saveMessage = "Fehler: Das Profil wurde nicht gefunden."
            return
        }

        var values = current.profileDetails[detailKey] ?? []
        let alreadyPresent = values.contains {
            $0.compare(
                cleanValue,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
        if !alreadyPresent {
            values.append(cleanValue)
            current.profileDetails[detailKey] = values
        }

        if saveSource,
           PublicWebResearchService.isSafePublicPageURL(candidate.url),
           !current.links.contains(where: {
               $0.resolvedURL.map(normalized) == normalized(candidate.url)
           }) {
            current.links.append(
                ProfileLink(
                    platform: ProfileLinkPlatform.inferred(from: candidate.url),
                    title: candidate.title,
                    url: candidate.url.absoluteString,
                    confirmed: true
                )
            )
        }

        do {
            try store.updatePerson(current)
            saveMessage = "Gespeichert"
        } catch {
            saveMessage = "Fehler: \(error.localizedDescription)"
        }
    }

    private func socialIcon(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("instagram") {
            return "camera.fill"
        }
        if host.contains("facebook") {
            return "person.2.fill"
        }
        return "globe.europe.africa.fill"
    }

    private func isSaved(_ url: URL) -> Bool {
        guard let current = store.person(id: person.id) else { return false }
        let candidate = normalized(url)
        return current.links.contains { link in
            guard let existing = link.resolvedURL else { return false }
            return normalized(existing) == candidate
        }
    }

    private func save(url: URL, title: String) {
        guard PublicWebResearchService.isSafePublicPageURL(url) else {
            saveMessage = "Fehler: Diese Adresse ist nicht als öffentliche HTTPS-Seite zugelassen."
            return
        }
        guard var current = store.person(id: person.id) else {
            saveMessage = "Fehler: Das Profil wurde nicht gefunden."
            return
        }
        guard !isSaved(url) else { return }

        current.links.append(
            ProfileLink(
                platform: ProfileLinkPlatform.inferred(from: url),
                title: title,
                url: url.absoluteString,
                confirmed: true
            )
        )

        do {
            try store.updatePerson(current)
            saveMessage = "Gespeichert"
        } catch {
            saveMessage = "Fehler: \(error.localizedDescription)"
        }
    }

    private func normalized(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if components.port == 443, components.scheme == "https" {
            components.port = nil
        }
        if var items = components.queryItems {
            let trackingNames = Set(["fbclid", "gclid", "mc_cid", "mc_eid"])
            items.removeAll { item in
                let name = item.name.lowercased()
                return name.hasPrefix("utm_") || trackingNames.contains(name)
            }
            components.queryItems = items.isEmpty ? nil : items
        }
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.string ?? url.absoluteString
    }
}

private enum ResearchImportDestination: String, CaseIterable, Identifiable {
    case organization = "organizations"
    case trainingPlace = "trainingPlaces"
    case publicFact = "confirmedPublicFacts"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .organization: "Verein oder Organisation"
        case .trainingPlace: "Trainingsort"
        case .publicFact: "Andere bestätigte Info"
        }
    }
}

private struct ResearchCandidateImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let candidate: PublicWebResult
    let onSave: (String, String, Bool) -> Void

    @State private var value: String
    @State private var destination: ResearchImportDestination = .organization
    @State private var saveSource = true

    init(
        candidate: PublicWebResult,
        onSave: @escaping (String, String, Bool) -> Void
    ) {
        self.candidate = candidate
        self.onSave = onSave
        _value = State(initialValue: candidate.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.berryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Geprüfte Angabe übernehmen")
                        .font(.title3.weight(.bold))
                    Text(candidate.hostLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "Bearbeite den Text so, dass nur die Information stehen bleibt, "
                    + "die du in der geöffneten Quelle wirklich bestätigt hast."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Picker("Speichern als", selection: $destination) {
                ForEach(ResearchImportDestination.allCases) { destination in
                    Text(destination.title).tag(destination)
                }
            }

            TextField("Bestätigte Angabe", text: $value)
                .textFieldStyle(.roundedBorder)

            Toggle("Öffentliche Quelle zusätzlich als Link speichern", isOn: $saveSource)
                .toggleStyle(.checkbox)

            Label(
                "Die App behauptet nicht automatisch, dass die Person Mitglied ist. Mit „Übernehmen“ bestätigst du die eingetragene Formulierung selbst.",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(AppTheme.coralText)
            .surfaceCard(padding: 10)

            HStack {
                Button("Abbrechen", role: .cancel) { dismiss() }
                Spacer()
                Button("Übernehmen") {
                    onSave(
                        value,
                        destination.rawValue,
                        saveSource
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
                .disabled(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

private struct SelectedPublicPage: Identifiable, Equatable {
    let url: URL

    var id: String { url.absoluteString }
    var host: String { PublicWebResearchService.displayHost(for: url) }
}

private struct PrivateSearchWebView: NSViewRepresentable {
    let searchURL: URL?
    let searchID: UUID
    @Binding var selectedPage: SelectedPublicPage?
    @Binding var message: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "Freundeblick/0.2 Websuche"
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let searchURL,
              context.coordinator.loadedSearchID != searchID
        else {
            return
        }

        context.coordinator.loadedSearchID = searchID
        var request = URLRequest(url: searchURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: PrivateSearchWebView
        var loadedSearchID: UUID?

        init(parent: PrivateSearchWebView) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }

            if let redirected = PublicWebResearchService.duckDuckGoRedirectTarget(from: url) {
                select(redirected)
                decisionHandler(.cancel)
                return
            }

            if PublicWebResearchService.isDuckDuckGoURL(url),
               url.scheme?.lowercased() == "https" {
                decisionHandler(.allow)
                return
            }

            if PublicWebResearchService.isSafePublicPageURL(url) {
                select(url)
            } else {
                parent.selectedPage = nil
                parent.message = "Dieser Treffer wurde blockiert: erlaubt sind nur öffentliche HTTPS-Seiten; private Netze und Personensuchdienste bleiben gesperrt."
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {
                if let redirected = PublicWebResearchService.duckDuckGoRedirectTarget(from: url) {
                    select(redirected)
                } else if PublicWebResearchService.isDuckDuckGoURL(url) {
                    webView.load(navigationAction.request)
                } else if PublicWebResearchService.isSafePublicPageURL(url) {
                    select(url)
                }
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            if (error as? URLError)?.code == .cancelled {
                return
            }
            parent.message = "Die Suchseite konnte nicht geladen werden: \(error.localizedDescription)"
        }

        private func select(_ url: URL) {
            guard PublicWebResearchService.isSafePublicPageURL(url) else {
                parent.selectedPage = nil
                parent.message = "Dieser Treffer wurde aus Sicherheitsgründen blockiert."
                return
            }
            parent.selectedPage = SelectedPublicPage(url: url)
            parent.message = nil
        }

    }
}
