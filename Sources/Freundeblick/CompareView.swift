import Charts
import SwiftUI

enum ComparisonEngine {
    private static let sensitiveProfileKeys = Set([
        "genderIdentity",
        "sexualOrientation",
    ])

    static func normalizedSet(_ values: [String]) -> Set<String> {
        Set(
            values
                .map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .folding(
                            options: [.caseInsensitive, .diacriticInsensitive],
                            locale: .current
                        )
                        .lowercased()
                }
                .filter { !$0.isEmpty }
        )
    }

    static func overlapPercentage(_ first: [String], _ second: [String]) -> Double {
        let left = normalizedSet(first)
        let right = normalizedSet(second)
        let union = left.union(right)
        guard !union.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(union.count) * 100
    }

    static func averageKnownOverlap(
        _ categories: [([String], [String])]
    ) -> Double? {
        let scores = categories.compactMap { first, second -> Double? in
            guard !normalizedSet(first).isEmpty,
                  !normalizedSet(second).isEmpty
            else {
                return nil
            }
            return overlapPercentage(first, second)
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    static func comparableProfileValues(
        _ details: [String: [String]]
    ) -> [String] {
        details
            .filter { !sensitiveProfileKeys.contains($0.key) }
            .values
            .flatMap { $0 }
    }

    static func sharedValues(_ collections: [[String]]) -> [String] {
        guard let first = collections.first else { return [] }
        let common = collections.dropFirst().reduce(normalizedSet(first)) {
            $0.intersection(normalizedSet($1))
        }
        return first
            .filter { common.contains(normalizedSet([$0]).first ?? "") }
            .reduce(into: [String]()) { result, value in
                if !result.contains(where: {
                    $0.localizedCaseInsensitiveCompare(value) == .orderedSame
                }) {
                    result.append(value)
                }
            }
    }
}

struct CompareView: View {
    @EnvironmentObject private var store: LibraryStore

    @Binding var selectedPersonID: UUID?
    @Binding var section: AppSection?

    @State private var selectedIDs = Set<UUID>()

    private let seriesColors = [
        AppTheme.plum,
        AppTheme.berry,
        AppTheme.coral,
        Color.orange,
    ]

    private var people: [Person] {
        store.data.people.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var selectedPeople: [Person] {
        people.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                selectionCard

                if people.count < 2 {
                    EmptyArtwork(
                        systemImage: "person.2.slash",
                        title: "Noch nicht genug Profile",
                        message: "Lege mindestens zwei Personen an, um Gemeinsamkeiten und Unterschiede darzustellen."
                    )
                    .frame(maxWidth: .infinity)
                    .surfaceCard()
                } else if selectedPeople.count < 2 {
                    EmptyArtwork(
                        systemImage: "person.2.badge.gearshape",
                        title: "Wähle mindestens zwei Personen",
                        message: "Du kannst zwei bis vier Profile gleichzeitig vergleichen."
                    )
                    .frame(maxWidth: .infinity)
                    .surfaceCard()
                } else {
                    similaritySummaryCard
                    chartArea
                    sharedDetails
                    personCards
                }
            }
            .padding(28)
            .frame(maxWidth: 1350, alignment: .leading)
        }
        .onAppear(perform: repairSelection)
        .onChange(of: people.map(\.id)) { _, _ in
            repairSelection()
        }
    }

    private var similaritySummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label("Gesamt-Übereinstimmung", systemImage: "percent")
                    .font(.headline)
                    .foregroundStyle(AppTheme.berry)
                Spacer()
                Text("Durchschnitt bekannter Bereiche")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 330), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(pairSimilarities.enumerated()), id: \.element.id) {
                    index,
                    similarity in
                    pairSimilarityCard(
                        similarity,
                        tint: seriesColors[index % seriesColors.count]
                    )
                }
            }

            Text(
                "Der Wert ist der Mittelwert aus Interessen, Gemüt und Steckbrief. "
                    + "Ein Bereich zählt nur, wenn bei beiden Personen Angaben vorhanden "
                    + "sind. Geschlecht und sexuelle Orientierung fließen nicht ein. "
                    + "Das ist eine Daten-Überschneidung, keine Bewertung der Freundschaft "
                    + "oder der Menschen."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .surfaceCard()
    }

    private func pairSimilarityCard(
        _ similarity: PairSimilarity,
        tint: Color
    ) -> some View {
        HStack(spacing: 16) {
            SimilarityRing(
                percentage: similarity.percentage,
                tint: tint
            )

            VStack(alignment: .leading, spacing: 9) {
                Text(similarity.pair)
                    .font(.callout.weight(.semibold))

                if similarity.percentage == nil {
                    Text("Noch nicht genug vergleichbare Angaben")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(similarity.categories) { category in
                            StatusPill(
                                text: "\(category.title) \(Int(category.percentage.rounded())) %",
                                systemImage: category.systemImage,
                                tint: tint
                            )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(tint.opacity(0.16))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            SectionTitle(
                title: "Menschen vergleichen",
                subtitle: "Gemeinsamkeiten und gespeicherte Angaben auf einen Blick"
            )
            Spacer()
            StatusPill(
                text: "keine Bewertung",
                systemImage: "equal.circle.fill",
                tint: AppTheme.plum
            )
        }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Profile auswählen", systemImage: "person.2.crop.square.stack.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.plum)
                Spacer()
                Text("\(selectedPeople.count) von maximal 4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 9) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    let isSelected = selectedIDs.contains(person.id)
                    Button {
                        toggle(person.id)
                    } label: {
                        Label(
                            person.name,
                            systemImage: isSelected
                                ? "checkmark.circle.fill"
                                : "person.crop.circle"
                        )
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? .white : color(for: index))
                        .background(
                            isSelected ? color(for: index) : color(for: index).opacity(0.1),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSelected && selectedIDs.count >= 4)
                }
            }

            Text("Die Diagramme vergleichen nur vorhandene Daten. Fehlende Angaben bedeuten nicht, dass eine Person weniger interessant oder weniger passend ist.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .surfaceCard()
    }

    @ViewBuilder
    private var chartArea: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                radarCard
                overlapCard
            }
            .frame(minWidth: 850)

            VStack(alignment: .leading, spacing: 16) {
                radarCard
                overlapCard
            }
        }

        countChartCard
    }

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Datenabdeckung", systemImage: "hexagon.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.plum)
            Text("Zeigt, zu welchen Bereichen bereits Angaben gespeichert sind.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ComparisonRadarChart(
                axes: radarAxes,
                series: selectedPeople.enumerated().map { index, person in
                    RadarSeries(
                        id: person.id,
                        name: person.name,
                        color: seriesColors[index % seriesColors.count],
                        values: radarValues(for: person)
                    )
                }
            )
            .frame(height: 330)

            chartLegend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private var overlapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gespeicherte Überschneidungen", systemImage: "circle.grid.2x2.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.berry)
            Text("Anteil gemeinsamer Einträge – unbekannte Angaben zählen nicht als Gemeinsamkeit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(overlapPoints) { point in
                BarMark(
                    x: .value("Gemeinsam", point.percentage),
                    y: .value("Bereich", point.category)
                )
                .foregroundStyle(by: .value("Paar", point.pair))
                .position(by: .value("Paar", point.pair))
                .annotation(position: .trailing) {
                    if point.percentage > 0 {
                        Text("\(Int(point.percentage.rounded())) %")
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text("\(number) %")
                        }
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: pairNames,
                range: pairNames.indices.map {
                    seriesColors[$0 % seriesColors.count]
                }
            )
            .frame(height: 330)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private var countChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gespeicherte Datenmenge", systemImage: "chart.bar.xaxis")
                .font(.headline)
                .foregroundStyle(AppTheme.coral)
            Text("Absolute Anzahl gespeicherter Einträge je Bereich – keine Punktzahl und keine Rangliste.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(countPoints) { point in
                BarMark(
                    x: .value("Bereich", point.metric),
                    y: .value("Anzahl", point.count)
                )
                .foregroundStyle(by: .value("Person", point.personName))
                .position(by: .value("Person", point.personName))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .chartForegroundStyleScale(
                domain: selectedPeople.map(\.name),
                range: selectedPeople.indices.map {
                    seriesColors[$0 % seriesColors.count]
                }
            )
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 280)

            chartLegend
        }
        .surfaceCard()
    }

    @ViewBuilder
    private var sharedDetails: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Was gemeinsam gespeichert ist", systemImage: "link.circle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.plum)

            sharedRow(
                title: "Interessen",
                values: ComparisonEngine.sharedValues(
                    selectedPeople.map(\.interests)
                ),
                tint: AppTheme.coral
            )
            sharedRow(
                title: "Gemüt",
                values: ComparisonEngine.sharedValues(
                    selectedPeople.map(\.temperamentTags)
                ),
                tint: AppTheme.plum
            )
            sharedRow(
                title: "Steckbrief-Werte",
                values: ComparisonEngine.sharedValues(
                    selectedPeople.map {
                        ComparisonEngine.comparableProfileValues($0.profileDetails)
                    }
                ),
                tint: AppTheme.berry
            )
        }
        .surfaceCard()
    }

    @ViewBuilder
    private func sharedRow(title: String, values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if values.isEmpty {
                Text("Keine gemeinsame gespeicherte Angabe")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(values, id: \.self) { value in
                        StatusPill(text: value, systemImage: "checkmark", tint: tint)
                    }
                }
            }
        }
    }

    private var personCards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 270), spacing: 14)],
            spacing: 14
        ) {
            ForEach(Array(selectedPeople.enumerated()), id: \.element.id) { index, person in
                ComparisonPersonCard(
                    person: person,
                    color: seriesColors[index % seriesColors.count],
                    connectionCount: store.mutualFriendIDs(for: person.id).count,
                    mediaCount: store.media(for: person.id).count
                ) {
                    selectedPersonID = person.id
                    section = .people
                }
            }
        }
    }

    private var chartLegend: some View {
        FlowLayout(spacing: 10) {
            ForEach(Array(selectedPeople.enumerated()), id: \.element.id) { index, person in
                HStack(spacing: 6) {
                    Circle()
                        .fill(seriesColors[index % seriesColors.count])
                        .frame(width: 9, height: 9)
                    Text(person.name)
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var radarAxes: [RadarAxis] {
        [
            RadarAxis(id: "basis", title: "Basis"),
            RadarAxis(id: "interests", title: "Interessen"),
            RadarAxis(id: "temperament", title: "Gemüt"),
            RadarAxis(id: "details", title: "Steckbrief"),
            RadarAxis(id: "network", title: "Netzwerk"),
            RadarAxis(id: "media", title: "Medien"),
        ]
    }

    private func radarValues(for person: Person) -> [Double] {
        let basicFields = [
            person.birthday != nil,
            person.location?.isEmpty == false,
            !person.summary.isEmpty,
            !person.aliases.isEmpty,
            !person.links.isEmpty,
        ].filter { $0 }.count
        return [
            Double(basicFields) / 5,
            min(Double(person.interests.count) / 8, 1),
            min(Double(person.temperamentTags.count) / 6, 1),
            min(
                Double(person.profileDetails.values.filter { !$0.isEmpty }.count) / 12,
                1
            ),
            min(Double(store.mutualFriendIDs(for: person.id).count) / 8, 1),
            min(Double(store.media(for: person.id).count) / 10, 1),
        ]
    }

    private var countPoints: [CountPoint] {
        selectedPeople.flatMap { person in
            [
                CountPoint(person: person, metric: "Interessen", count: person.interests.count),
                CountPoint(person: person, metric: "Gemüt", count: person.temperamentTags.count),
                CountPoint(
                    person: person,
                    metric: "Steckbrief",
                    count: person.profileDetails.values.filter { !$0.isEmpty }.count
                ),
                CountPoint(
                    person: person,
                    metric: "Verbindungen",
                    count: store.mutualFriendIDs(for: person.id).count
                ),
                CountPoint(
                    person: person,
                    metric: "Medien",
                    count: store.media(for: person.id).count
                ),
            ]
        }
    }

    private var personPairs: [(Person, Person)] {
        var result: [(Person, Person)] = []
        for leftIndex in selectedPeople.indices {
            for rightIndex in selectedPeople.indices where rightIndex > leftIndex {
                result.append((selectedPeople[leftIndex], selectedPeople[rightIndex]))
            }
        }
        return result
    }

    private var pairNames: [String] {
        personPairs.map { "\($0.0.name) ↔ \($0.1.name)" }
    }

    private var overlapPoints: [OverlapPoint] {
        personPairs.flatMap { first, second in
            let pair = "\(first.name) ↔ \(second.name)"
            return [
                OverlapPoint(
                    pair: pair,
                    category: "Interessen",
                    percentage: ComparisonEngine.overlapPercentage(
                        first.interests,
                        second.interests
                    )
                ),
                OverlapPoint(
                    pair: pair,
                    category: "Gemüt",
                    percentage: ComparisonEngine.overlapPercentage(
                        first.temperamentTags,
                        second.temperamentTags
                    )
                ),
                OverlapPoint(
                    pair: pair,
                    category: "Steckbrief",
                    percentage: ComparisonEngine.overlapPercentage(
                        ComparisonEngine.comparableProfileValues(first.profileDetails),
                        ComparisonEngine.comparableProfileValues(second.profileDetails)
                    )
                ),
            ]
        }
    }

    private var pairSimilarities: [PairSimilarity] {
        personPairs.map { first, second in
            let categories = similarityCategories(first: first, second: second)
            return PairSimilarity(
                firstID: first.id,
                secondID: second.id,
                pair: "\(first.name) ↔ \(second.name)",
                percentage: ComparisonEngine.averageKnownOverlap(
                    categories.map { ($0.firstValues, $0.secondValues) }
                ),
                categories: categories.compactMap { category in
                    guard !ComparisonEngine.normalizedSet(category.firstValues).isEmpty,
                          !ComparisonEngine.normalizedSet(category.secondValues).isEmpty
                    else {
                        return nil
                    }
                    return SimilarityCategoryResult(
                        title: category.title,
                        systemImage: category.systemImage,
                        percentage: ComparisonEngine.overlapPercentage(
                            category.firstValues,
                            category.secondValues
                        )
                    )
                }
            )
        }
    }

    private func similarityCategories(
        first: Person,
        second: Person
    ) -> [SimilarityCategoryInput] {
        [
            SimilarityCategoryInput(
                title: "Interessen",
                systemImage: "sparkles",
                firstValues: first.interests,
                secondValues: second.interests
            ),
            SimilarityCategoryInput(
                title: "Gemüt",
                systemImage: "heart.fill",
                firstValues: first.temperamentTags,
                secondValues: second.temperamentTags
            ),
            SimilarityCategoryInput(
                title: "Steckbrief",
                systemImage: "list.bullet.clipboard.fill",
                firstValues: ComparisonEngine.comparableProfileValues(
                    first.profileDetails
                ),
                secondValues: ComparisonEngine.comparableProfileValues(
                    second.profileDetails
                )
            ),
        ]
    }

    private func color(for personIndex: Int) -> Color {
        seriesColors[personIndex % seriesColors.count]
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else if selectedIDs.count < 4 {
            selectedIDs.insert(id)
        }
    }

    private func repairSelection() {
        let availableIDs = Set(people.map(\.id))
        selectedIDs.formIntersection(availableIDs)
        if selectedIDs.count < min(2, people.count) {
            for person in people where selectedIDs.count < min(3, people.count) {
                selectedIDs.insert(person.id)
            }
        }
    }
}

private struct CountPoint: Identifiable {
    let id = UUID()
    let personID: UUID
    let personName: String
    let metric: String
    let count: Int

    init(person: Person, metric: String, count: Int) {
        personID = person.id
        personName = person.name
        self.metric = metric
        self.count = count
    }
}

private struct OverlapPoint: Identifiable {
    let id = UUID()
    let pair: String
    let category: String
    let percentage: Double
}

private struct SimilarityCategoryInput {
    let title: String
    let systemImage: String
    let firstValues: [String]
    let secondValues: [String]
}

private struct SimilarityCategoryResult: Identifiable {
    let title: String
    let systemImage: String
    let percentage: Double

    var id: String { title }
}

private struct PairSimilarity: Identifiable {
    let firstID: UUID
    let secondID: UUID
    let pair: String
    let percentage: Double?
    let categories: [SimilarityCategoryResult]

    var id: String { "\(firstID.uuidString)-\(secondID.uuidString)" }
}

private struct SimilarityRing: View {
    let percentage: Double?
    let tint: Color

    private var progress: Double {
        min(max((percentage ?? 0) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: 9)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(percentage.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.title2.weight(.bold))
                Text("%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 78, height: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gesamt-Übereinstimmung")
        .accessibilityValue(
            percentage.map { "\(Int($0.rounded())) Prozent" }
                ?? "Nicht genug vergleichbare Angaben"
        )
    }
}

private struct RadarAxis: Identifiable {
    let id: String
    let title: String
}

private struct RadarSeries: Identifiable {
    let id: UUID
    let name: String
    let color: Color
    let values: [Double]
}

private struct ComparisonRadarChart: View {
    let axes: [RadarAxis]
    let series: [RadarSeries]

    var body: some View {
        Canvas { context, size in
            guard axes.count >= 3 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(40, min(size.width, size.height) * 0.34)

            for level in 1...4 {
                let levelRadius = radius * CGFloat(level) / 4
                let polygon = path(
                    values: Array(repeating: 1, count: axes.count),
                    center: center,
                    radius: levelRadius
                )
                context.stroke(
                    polygon,
                    with: .color(.secondary.opacity(level == 4 ? 0.28 : 0.13)),
                    lineWidth: 1
                )
            }

            for index in axes.indices {
                let point = polarPoint(
                    index: index,
                    count: axes.count,
                    center: center,
                    radius: radius
                )
                var axisPath = Path()
                axisPath.move(to: center)
                axisPath.addLine(to: point)
                context.stroke(
                    axisPath,
                    with: .color(.secondary.opacity(0.18)),
                    lineWidth: 1
                )

                let labelPoint = polarPoint(
                    index: index,
                    count: axes.count,
                    center: center,
                    radius: radius + 25
                )
                context.draw(
                    Text(axes[index].title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary),
                    at: labelPoint,
                    anchor: .center
                )
            }

            for item in series {
                let values = axes.indices.map { index in
                    min(max(item.values[safe: index] ?? 0, 0), 1)
                }
                let polygon = path(
                    values: values,
                    center: center,
                    radius: radius
                )
                context.fill(polygon, with: .color(item.color.opacity(0.13)))
                context.stroke(polygon, with: .color(item.color), lineWidth: 2.5)

                for index in values.indices {
                    let point = polarPoint(
                        index: index,
                        count: values.count,
                        center: center,
                        radius: radius * values[index]
                    )
                    let marker = Path(
                        ellipseIn: CGRect(
                            x: point.x - 3.5,
                            y: point.y - 3.5,
                            width: 7,
                            height: 7
                        )
                    )
                    context.fill(marker, with: .color(item.color))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Radar-Diagramm zur gespeicherten Datenabdeckung")
        .accessibilityValue(
            series.map { "\($0.name): \($0.values.map { Int($0 * 100) })" }
                .joined(separator: "; ")
        )
    }

    private func path(
        values: [Double],
        center: CGPoint,
        radius: CGFloat
    ) -> Path {
        var result = Path()
        for index in values.indices {
            let point = polarPoint(
                index: index,
                count: values.count,
                center: center,
                radius: radius * values[index]
            )
            if index == values.startIndex {
                result.move(to: point)
            } else {
                result.addLine(to: point)
            }
        }
        result.closeSubpath()
        return result
    }

    private func polarPoint(
        index: Int,
        count: Int,
        center: CGPoint,
        radius: CGFloat
    ) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(count)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

private struct ComparisonPersonCard: View {
    let person: Person
    let color: Color
    let connectionCount: Int
    let mediaCount: Int
    let openProfile: () -> Void

    private var savedDetails: [(String, [String])] {
        person.profileDetails
            .filter { !$0.value.isEmpty }
            .map { ($0.key, $0.value) }
            .sorted {
                ProfileSuggestionCatalog.displayLabel(for: $0.0)
                    .localizedCaseInsensitiveCompare(
                        ProfileSuggestionCatalog.displayLabel(for: $1.0)
                    ) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(.headline)
                    Text(
                        [
                            person.age().map { "\($0) J." },
                            person.location,
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Profil", action: openProfile)
                    .buttonStyle(.bordered)
                    .tint(color)
            }

            HStack(spacing: 12) {
                Label("\(connectionCount)", systemImage: "person.2.fill")
                Label("\(mediaCount)", systemImage: "photo.stack.fill")
                Label(
                    "\(savedDetails.count)",
                    systemImage: "list.bullet.clipboard.fill"
                )
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)

            if !person.interests.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(person.interests.prefix(5), id: \.self) { interest in
                        Text(interest)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(color.opacity(0.1), in: Capsule())
                    }
                }
            }

            ForEach(Array(savedDetails.prefix(6)), id: \.0) { key, values in
                HStack(alignment: .firstTextBaseline) {
                    Text(ProfileSuggestionCatalog.displayLabel(for: key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(values.joined(separator: ", "))
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                }
            }

            if savedDetails.count > 6 {
                Text("+ \(savedDetails.count - 6) weitere Steckbriefangaben")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
