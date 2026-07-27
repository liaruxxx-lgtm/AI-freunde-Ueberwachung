import SwiftUI

struct AssistantAccessView: View {
    @EnvironmentObject private var store: LibraryStore

    let initialQuestion: String
    @Binding var selectedPersonID: UUID?
    @Binding var section: AppSection?

    @State private var question = ""
    @State private var answer: QueryAnswer?
    @State private var researchPerson: Person?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                queryBox

                if let answer {
                    QueryAnswerCard(answer: answer) { personID in
                        selectedPersonID = personID
                        section = .people
                    }
                } else {
                    examples
                }

                accessInfo
            }
            .padding(28)
            .frame(maxWidth: 900)
        }
        .onAppear {
            if question.isEmpty {
                question = initialQuestion
                if !question.isEmpty { ask() }
            }
        }
        .onChange(of: initialQuestion) { _, newValue in
            guard !newValue.isEmpty, newValue != question else { return }
            question = newValue
            ask()
        }
        .sheet(item: $researchPerson) { person in
            WebResearchView(person: person)
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                SectionTitle(title: "Frag Freundeblick", subtitle: "Kurze Antwort, visuelle Details")
            }
            Spacer()
            StatusPill(text: "Lesen & Schreiben", systemImage: "pencil.and.list.clipboard", tint: AppTheme.plumText)
        }
    }

    private var queryBox: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title2)
                .foregroundStyle(AppTheme.berryText)
            TextField("z. B. Mit wem ist Leni befreundet?", text: $question)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit(ask)
            Button(action: ask) {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.berry)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .surfaceCard()
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Beispiele")
                .font(.headline)
            FlowLayout(spacing: 9) {
                ForEach([
                    "Wer ist Leni?",
                    "Wie alt ist Nika?",
                    "Wo wohnt Leni?",
                    "Mit wem ist Nika befreundet?",
                    "Recherchiere im Internet nach Leni",
                    "Welche Gruppen gibt es?"
                ], id: \.self) { example in
                    Button(example) {
                        question = example
                        ask()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .surfaceCard()
    }

    private var accessInfo: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.plumText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex-Verbindung vorbereitet")
                        .font(.headline)
                    Text("Projektlokaler MCP-Dienst · Profile, Beziehungen und Medienvorschauen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: "lokal", systemImage: "desktopcomputer", tint: AppTheme.plumText)
            }

            Divider()

            Label("Codex darf Profile, Links, Beziehungen und Beobachtungen speichern.", systemImage: "square.and.pencil")
                .font(.callout)
            Label("Es gibt keine Löschwerkzeuge; neue Beobachtungen bleiben zunächst unbestätigt.", systemImage: "checkmark.shield.fill")
                .font(.callout)
            Label("Originalmedien und Gesichtsmerkmale werden nicht über die Schnittstelle ausgegeben.", systemImage: "photo.badge.checkmark")
                .font(.callout)
            Label("Nach dem ersten Build Codex einmal neu starten, damit der MCP-Dienst geladen wird.", systemImage: "arrow.clockwise")
                .font(.callout)
        }
        .surfaceCard()
    }

    private func ask() {
        if isInternetResearchRequest(question) {
            let matches = internetResearchMatches(for: question)
            if matches.count == 1, let person = matches.first {
                answer = QueryAnswer(
                    kind: .links,
                    title: "Web-Recherche für \(person.name)",
                    subtitle: "Prüfe den sichtbaren Suchtext und starte die öffentliche Suche.",
                    personIDs: [person.id]
                )
                researchPerson = person
            } else if matches.isEmpty {
                answer = QueryAnswer(
                    kind: .notFound,
                    title: "Person nicht gefunden",
                    subtitle: "Lege das Profil zuerst an oder nenne einen gespeicherten Namen."
                )
            } else {
                answer = QueryAnswer(
                    kind: .notFound,
                    title: "Bitte genauer zuordnen",
                    subtitle: "Mehrere Profile passen zu diesem Namen. Nenne den vollständigen gespeicherten Namen."
                )
            }
            return
        }
        answer = store.answer(question)
    }

    private func isInternetResearchRequest(_ value: String) -> Bool {
        let normalizedQuestion = normalized(value)
        return (
            normalizedQuestion.contains("recherch")
                || normalizedQuestion.contains("such")
                || normalizedQuestion.contains("find")
        ) && (
            normalizedQuestion.contains("internet")
                || normalizedQuestion.contains("web")
                || normalizedQuestion.contains("online")
        )
    }

    private func internetResearchMatches(for value: String) -> [Person] {
        let normalizedQuestion = normalized(value)
        var candidates: [(person: Person, name: String)] = []
        for person in store.data.people {
            var names = person.allNames
            if let firstName = person.name.split(whereSeparator: \.isWhitespace).first {
                names.append(String(firstName))
            }
            for name in names {
                candidates.append((person: person, name: normalized(name)))
            }
        }

        let matched = candidates.filter {
            !$0.name.isEmpty
                && (
                    containsPhrase($0.name, in: normalizedQuestion)
                        || containsPhrase(
                            $0.name.hasSuffix("s") ? $0.name : $0.name + "s",
                            in: normalizedQuestion
                        )
                )
        }
        guard let longestMatch = matched.map(\.name.count).max() else {
            return []
        }

        var seen = Set<UUID>()
        return matched
            .filter { $0.name.count == longestMatch }
            .compactMap { candidate in
                seen.insert(candidate.person.id).inserted ? candidate.person : nil
            }
    }

    private func normalized(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return String(
            folded.unicodeScalars.map {
                CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
            }
        )
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }

    private func containsPhrase(_ phrase: String, in value: String) -> Bool {
        value == phrase
            || value.hasPrefix(phrase + " ")
            || value.hasSuffix(" " + phrase)
            || value.contains(" " + phrase + " ")
    }
}

private struct QueryAnswerCard: View {
    let answer: QueryAnswer
    let openPerson: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: answer.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 5) {
                    Text(answer.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(answer.summary)
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer()
            }

            if !answer.items.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(answer.items) { item in
                        QueryAnswerItemCard(
                            item: item,
                            opensWebLink: answer.kind == .links
                        )
                    }
                }
            }

            if let personID = answer.personID {
                Button("Profil visuell öffnen") {
                    openPerson(personID)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
            }
        }
        .surfaceCard(padding: 22)
    }
}

private struct QueryAnswerItemCard: View {
    @Environment(\.openURL) private var openURL

    let item: QueryAnswerItem
    let opensWebLink: Bool

    var body: some View {
        SwiftUI.Group {
            if let webURL {
                Button {
                    openURL(webURL)
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .help("Link im Browser öffnen")
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 11) {
            Image(systemName: item.symbolName)
                .font(.title3)
                .foregroundStyle(AppTheme.berryText)
                .frame(width: 38, height: 38)
                .background(
                    AppTheme.berry.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)
            }
            Spacer(minLength: 2)
            if webURL != nil {
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 11)
    }

    private var webURL: URL? {
        guard opensWebLink,
              let separator = item.value.range(of: " · ", options: .backwards)
        else {
            return nil
        }
        let value = String(item.value[separator.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              PublicWebResearchService.isSafePublicPageURL(url)
        else {
            return nil
        }
        return url
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrangedSubviews(
            maximumWidth: proposal.width ?? .greatestFiniteMagnitude,
            subviews: subviews
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrangedSubviews(
            maximumWidth: bounds.width,
            subviews: subviews
        )

        for (index, origin) in arrangement.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func arrangedSubviews(
        maximumWidth: CGFloat,
        subviews: Subviews
    ) -> (size: CGSize, origins: [CGPoint]) {
        guard !subviews.isEmpty else {
            return (.zero, [])
        }

        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maximumWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }

            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widestRow = max(widestRow, x - spacing)
        }

        return (
            CGSize(width: min(widestRow, maximumWidth), height: y + rowHeight),
            origins
        )
    }
}
