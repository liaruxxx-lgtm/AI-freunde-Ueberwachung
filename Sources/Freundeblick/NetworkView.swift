import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var store: LibraryStore

    @Binding var selectedPersonID: UUID?
    @Binding var section: AppSection?

    @State private var selectedKind: RelationshipKind?
    @State private var showingNetworkManagement = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                SectionTitle(
                    title: "Beziehungsnetz",
                    subtitle: "Automatische Vorschläge und manuell gepflegte Verbindungen an einem Ort"
                )
                Spacer()
                Picker("Filter", selection: $selectedKind) {
                    Text("Alle").tag(RelationshipKind?.none)
                    ForEach(RelationshipKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(Optional(kind))
                    }
                }
                .frame(width: 170)

                Button {
                    showingNetworkManagement = true
                } label: {
                    Label("Netzwerk verwalten", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
            }
            .padding(24)

            if store.data.people.isEmpty {
                Spacer()
                EmptyArtwork(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    title: "Das Netzwerk ist noch leer",
                    message: "Lege Personen und Beziehungen an. Gegenseitige Freundschaften bilden automatisch sichtbare Gruppen."
                )
                Spacer()
            } else {
                GeometryReader { geometry in
                    graph(in: geometry.size)
                }
                .background(
                    RadialGradient(
                        colors: [.white.opacity(0.85), AppTheme.apricot.opacity(0.12)],
                        center: .center,
                        startRadius: 40,
                        endRadius: 520
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    legend
                        .padding(18)
                }
                .padding([.horizontal, .bottom], 24)
            }
        }
        .sheet(isPresented: $showingNetworkManagement) {
            NetworkManagementView()
                .environmentObject(store)
        }
    }

    private func graph(in size: CGSize) -> some View {
        let people = store.data.people
        let positions = positions(for: people, in: size)
        let claims = filteredClaims

        return ZStack {
            Canvas { context, _ in
                for claim in claims {
                    guard let start = positions[claim.fromPersonID],
                          let end = positions[claim.toPersonID] else { continue }

                    let isMutual = claims.contains {
                        $0.fromPersonID == claim.toPersonID &&
                        $0.toPersonID == claim.fromPersonID &&
                        $0.kind == claim.kind
                    }

                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    context.stroke(
                        path,
                        with: .color(color(for: claim.kind).opacity(isMutual ? 0.72 : 0.28)),
                        style: StrokeStyle(
                            lineWidth: isMutual ? 4 : 2,
                            lineCap: .round,
                            dash: isMutual ? [] : [7, 6]
                        )
                    )
                }
            }

            ForEach(people) { person in
                if let point = positions[person.id] {
                    GraphPersonNode(
                        person: person,
                        selected: selectedPersonID == person.id
                    ) {
                        selectedPersonID = person.id
                        section = .people
                    }
                    .position(point)
                }
            }
        }
    }

    private var filteredClaims: [RelationshipClaim] {
        guard let selectedKind else { return store.data.relationshipClaims }
        return store.data.relationshipClaims.filter { $0.kind == selectedKind }
    }

    private func positions(for people: [Person], in size: CGSize) -> [UUID: CGPoint] {
        guard !people.isEmpty else { return [:] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(110, min(size.width, size.height) * 0.34)
        var result: [UUID: CGPoint] = [:]

        for (index, person) in people.enumerated() {
            let angle = (Double(index) / Double(people.count)) * (Double.pi * 2) - Double.pi / 2
            let ringOffset = people.count > 9 && index % 2 == 1 ? 0.72 : 1.0
            result[person.id] = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius * ringOffset,
                y: center.y + CGFloat(sin(angle)) * radius * ringOffset
            )
        }
        return result
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(RelationshipKind.allCases, id: \.self) { kind in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: kind))
                        .frame(width: 8, height: 8)
                    Text(kind.displayName)
                        .font(.caption)
                }
            }
            Divider().frame(height: 18)
            Text("gestrichelt = einseitig")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func color(for kind: RelationshipKind) -> Color {
        switch kind {
        case .friendship: AppTheme.berry
        case .family: .blue
        case .romantic: .pink
        case .school: .purple
        case .work: .orange
        case .acquaintance: .gray
        case .other: .secondary
        }
    }
}

private enum NetworkManagementSection: String, CaseIterable, Identifiable {
    case connections
    case groups

    var id: Self { self }

    var title: String {
        switch self {
        case .connections: "Verbindungen"
        case .groups: "Freundesgruppen"
        }
    }
}

private struct NetworkConnection: Identifiable {
    let id: String
    let firstPersonID: UUID
    let secondPersonID: UUID
    let firstPersonName: String
    let secondPersonName: String
    let kind: RelationshipKind
    let familyRole: FamilyRelationshipRole?
    let claims: [RelationshipClaim]

    var isMutual: Bool {
        claims.contains {
            $0.fromPersonID == firstPersonID && $0.toPersonID == secondPersonID
        } && claims.contains {
            $0.fromPersonID == secondPersonID && $0.toPersonID == firstPersonID
        }
    }

    var notes: String {
        claims.first(where: { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .notes ?? ""
    }

    var sourceLabel: String {
        let sources = Set(claims.map(\.source))
        if sources.count == 1, let source = sources.first {
            return source.germanLabel
        }
        return "Mehrere Quellen"
    }

    static func rows(from data: LibraryData) -> [NetworkConnection] {
        struct PairKey: Hashable {
            let lowID: UUID
            let highID: UUID
            let kind: RelationshipKind
        }

        let peopleByID = Dictionary(uniqueKeysWithValues: data.people.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: data.relationshipClaims) { claim in
            let ids = [claim.fromPersonID, claim.toPersonID].sorted {
                $0.uuidString < $1.uuidString
            }
            return PairKey(lowID: ids[0], highID: ids[1], kind: claim.kind)
        }

        return grouped.compactMap { key, claims -> NetworkConnection? in
            guard let firstClaim = claims.first,
                  peopleByID[firstClaim.fromPersonID] != nil,
                  peopleByID[firstClaim.toPersonID] != nil
            else {
                return nil
            }

            let hasBothDirections = claims.contains {
                $0.fromPersonID == firstClaim.toPersonID
                    && $0.toPersonID == firstClaim.fromPersonID
            }
            let orderedIDs: [UUID]
            if hasBothDirections {
                orderedIDs = [key.lowID, key.highID].sorted {
                    let lhs = peopleByID[$0]?.name ?? ""
                    let rhs = peopleByID[$1]?.name ?? ""
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
            } else {
                orderedIDs = [firstClaim.fromPersonID, firstClaim.toPersonID]
            }

            let role = claims.first {
                $0.fromPersonID == orderedIDs[0] && $0.toPersonID == orderedIDs[1]
            }?.familyRole ?? claims.first {
                $0.fromPersonID == orderedIDs[1] && $0.toPersonID == orderedIDs[0]
            }?.familyRole?.inverse

            return NetworkConnection(
                id: "\(key.lowID.uuidString)-\(key.highID.uuidString)-\(key.kind.rawValue)",
                firstPersonID: orderedIDs[0],
                secondPersonID: orderedIDs[1],
                firstPersonName: peopleByID[orderedIDs[0]]?.name ?? "Unbekannt",
                secondPersonName: peopleByID[orderedIDs[1]]?.name ?? "Unbekannt",
                kind: key.kind,
                familyRole: role,
                claims: claims
            )
        }
        .sorted {
            let lhs = "\($0.firstPersonName) \($0.secondPersonName) \($0.kind.rawValue)"
            let rhs = "\($1.firstPersonName) \($1.secondPersonName) \($1.kind.rawValue)"
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}

private struct ConnectionEditorRequest: Identifiable {
    let id = UUID()
    let connection: NetworkConnection?
}

private enum NetworkDeletionTarget {
    case connection(NetworkConnection)
    case group(Group)
}

private struct NetworkDeletionRequest: Identifiable {
    let id = UUID()
    let target: NetworkDeletionTarget
}

private struct NetworkManagementView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSection: NetworkManagementSection = .connections
    @State private var connectionEditor: ConnectionEditorRequest?
    @State private var groupEditor: Group?
    @State private var showingNewGroup = false
    @State private var pendingDeletion: NetworkDeletionRequest?
    @State private var errorMessage: String?

    private var connections: [NetworkConnection] {
        NetworkConnection.rows(from: store.data)
    }

    private var manualGroups: [Group] {
        store.data.groups
            .filter { $0.status == .manual }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var inferredGroups: [Group] {
        store.data.groups
            .filter { $0.status == .inferred }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Netzwerk verwalten")
                        .font(.title2.weight(.bold))
                    Text("Manuelle Angaben bleiben bearbeitbar; Vorschläge werden deutlich gekennzeichnet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            Picker("Bereich", selection: $selectedSection) {
                ForEach(NetworkManagementSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            switch selectedSection {
            case .connections:
                connectionsContent
            case .groups:
                groupsContent
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 650)
        .sheet(item: $connectionEditor) { request in
            NetworkConnectionEditorView(connection: request.connection)
                .environmentObject(store)
        }
        .sheet(item: $groupEditor) { group in
            NetworkGroupEditorView(group: group)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingNewGroup) {
            NetworkGroupEditorView(group: nil)
                .environmentObject(store)
        }
        .alert("Aktion nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
            Button(deletionButtonTitle, role: .destructive, action: performDeletion)
        } message: {
            Text(deletionMessage)
        }
    }

    private var connectionsContent: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Label(
                    "Familie und Verwandtschaft werden immer ausdrücklich zwischen zwei Personen gespeichert. Daraus entstehen keine weiteren Familienverbindungen.",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.blue)
                Spacer()
                Button {
                    connectionEditor = ConnectionEditorRequest(connection: nil)
                } label: {
                    Label("Verbindung hinzufügen", systemImage: "link.badge.plus")
                }
                .disabled(store.data.people.count < 2)
            }
            .padding(.horizontal, 20)

            if connections.isEmpty {
                ContentUnavailableView(
                    "Noch keine Verbindungen",
                    systemImage: "link.badge.plus",
                    description: Text("Lege eine Freundschaft, Familien- oder andere Verbindung manuell an.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(connections) { connection in
                            connectionRow(connection)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func connectionRow(_ connection: NetworkConnection) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol(for: connection.kind))
                .font(.title3)
                .foregroundStyle(color(for: connection.kind))
                .frame(width: 34, height: 34)
                .background(color(for: connection.kind).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(connection.firstPersonName)
                        .fontWeight(.semibold)
                    Image(systemName: connection.isMutual ? "arrow.left.arrow.right" : "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(connection.secondPersonName)
                        .fontWeight(.semibold)
                }
                HStack(spacing: 8) {
                    Text(connection.kind.germanLabel)
                    if let role = connection.familyRole {
                        Text("· \(role.germanLabel)")
                    }
                    Text("· \(connection.isMutual ? "gegenseitig" : "einseitig")")
                    Text("· \(connection.sourceLabel)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !connection.notes.isEmpty {
                    Text(connection.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                connectionEditor = ConnectionEditorRequest(connection: connection)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .help("Verbindung bearbeiten")

            Button(role: .destructive) {
                pendingDeletion = NetworkDeletionRequest(target: .connection(connection))
            } label: {
                Label("Löschen", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Verbindung löschen")
        }
        .surfaceCard(padding: 14)
    }

    private var groupsContent: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Label(
                    "Gegenseitige Freundschaften können automatisch eine Gruppe vorschlagen. Manuelle Gruppen kannst du frei anlegen und jederzeit bearbeiten.",
                    systemImage: "sparkles"
                )
                .font(.caption)
                .foregroundStyle(AppTheme.plum)
                Spacer()
                Button {
                    showingNewGroup = true
                } label: {
                    Label("Gruppe hinzufügen", systemImage: "person.3.sequence.fill")
                }
                .disabled(store.data.people.count < 2)
            }
            .padding(.horizontal, 20)

            if manualGroups.isEmpty && inferredGroups.isEmpty {
                ContentUnavailableView(
                    "Noch keine Freundesgruppen",
                    systemImage: "person.3",
                    description: Text("Lege eine Gruppe manuell an oder speichere gegenseitige Freundschaften.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if !manualGroups.isEmpty {
                            Text("Manuell gepflegt")
                                .font(.headline)
                            ForEach(manualGroups) { group in
                                groupRow(group, inferred: false)
                            }
                        }

                        if !inferredGroups.isEmpty {
                            Text("Automatisch vorgeschlagen")
                                .font(.headline)
                                .padding(.top, manualGroups.isEmpty ? 0 : 8)
                            ForEach(inferredGroups) { group in
                                groupRow(group, inferred: true)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func groupRow(_ group: Group, inferred: Bool) -> some View {
        let names = group.memberIDs.compactMap { store.person(id: $0)?.name }
        return HStack(spacing: 14) {
            Image(systemName: inferred ? "sparkles" : "person.3.fill")
                .font(.title3)
                .foregroundStyle(inferred ? AppTheme.coral : AppTheme.berry)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(group.name)
                    .fontWeight(.semibold)
                Text(names.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if inferred {
                    Text(group.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                groupEditor = group
            } label: {
                Label(inferred ? "Übernehmen und bearbeiten" : "Bearbeiten", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .help(inferred ? "Als manuelle Gruppe übernehmen und bearbeiten" : "Gruppe bearbeiten")

            Button(role: .destructive) {
                pendingDeletion = NetworkDeletionRequest(target: .group(group))
            } label: {
                Label(inferred ? "Vorschlag ausblenden" : "Löschen", systemImage: inferred ? "eye.slash" : "trash")
                    .labelStyle(.iconOnly)
            }
            .help(inferred ? "Diesen Vorschlag ausblenden" : "Gruppe löschen")
        }
        .surfaceCard(padding: 14)
    }

    private var deletionTitle: String {
        guard let pendingDeletion else { return "Löschen?" }
        switch pendingDeletion.target {
        case .connection:
            return "Verbindung löschen?"
        case let .group(group):
            return group.status == .inferred ? "Vorschlag ausblenden?" : "Gruppe löschen?"
        }
    }

    private var deletionButtonTitle: String {
        guard let pendingDeletion else { return "Löschen" }
        if case let .group(group) = pendingDeletion.target, group.status == .inferred {
            return "Ausblenden"
        }
        return "Löschen"
    }

    private var deletionMessage: String {
        guard let pendingDeletion else { return "" }
        switch pendingDeletion.target {
        case let .connection(connection):
            return "Die Verbindung zwischen \(connection.firstPersonName) und \(connection.secondPersonName) wird in beiden Richtungen entfernt."
        case let .group(group):
            if group.status == .inferred {
                return "Der automatische Vorschlag „\(group.name)“ wird abgelehnt und nicht erneut vorgeschlagen."
            }
            return "Die manuelle Gruppe „\(group.name)“ wird gelöscht. Die einzelnen Beziehungen bleiben erhalten."
        }
    }

    private func performDeletion() {
        guard let request = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            switch request.target {
            case let .connection(connection):
                try store.deleteRelationshipPair(
                    between: connection.firstPersonID,
                    and: connection.secondPersonID,
                    kind: connection.kind
                )
            case var .group(group):
                if group.status == .inferred {
                    group.status = .rejected
                    try store.updateGroup(group)
                } else {
                    try store.deleteGroup(id: group.id)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func color(for kind: RelationshipKind) -> Color {
        switch kind {
        case .friendship: AppTheme.berry
        case .family: .blue
        case .romantic: .pink
        case .school: .purple
        case .work: .orange
        case .acquaintance: .gray
        case .other: .secondary
        }
    }

    private func symbol(for kind: RelationshipKind) -> String {
        switch kind {
        case .friendship: "person.2.fill"
        case .family: "house.and.flag.fill"
        case .romantic: "heart.fill"
        case .school: "graduationcap.fill"
        case .work: "briefcase.fill"
        case .acquaintance: "person.wave.2.fill"
        case .other: "link"
        }
    }
}

private struct NetworkConnectionEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let connection: NetworkConnection?

    @State private var firstPersonID: UUID?
    @State private var secondPersonID: UUID?
    @State private var kind: RelationshipKind
    @State private var familyRole: FamilyRelationshipRole
    @State private var mutual: Bool
    @State private var notes: String
    @State private var errorMessage: String?

    init(connection: NetworkConnection?) {
        self.connection = connection
        _firstPersonID = State(initialValue: connection?.firstPersonID)
        _secondPersonID = State(initialValue: connection?.secondPersonID)
        _kind = State(initialValue: connection?.kind ?? .friendship)
        _familyRole = State(initialValue: connection?.familyRole ?? .familyMember)
        _mutual = State(initialValue: connection?.isMutual ?? true)
        _notes = State(initialValue: connection?.notes ?? "")
    }

    private var sortedPeople: [Person] {
        store.data.people.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var secondPersonChoices: [Person] {
        sortedPeople.filter { $0.id != firstPersonID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(connection == nil ? "Verbindung hinzufügen" : "Verbindung bearbeiten")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                    .disabled(firstPersonID == nil || secondPersonID == nil)
            }
            .padding(20)
            Divider()

            Form {
                Picker("Erste Person", selection: $firstPersonID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(sortedPeople) { person in
                        Text(person.name).tag(Optional(person.id))
                    }
                }
                .disabled(connection != nil)

                Picker("Andere Person", selection: $secondPersonID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(secondPersonChoices) { person in
                        Text(person.name).tag(Optional(person.id))
                    }
                }
                .disabled(connection != nil || firstPersonID == nil)

                Picker("Beziehung", selection: $kind) {
                    ForEach(RelationshipKind.allCases, id: \.self) { kind in
                        Text(kind.germanLabel).tag(kind)
                    }
                }

                if kind == .family {
                    Picker("Verwandtschaft der zweiten Person", selection: $familyRole) {
                        ForEach(FamilyRelationshipRole.allCases, id: \.self) { role in
                            Text(role.germanLabel).tag(role)
                        }
                    }
                }

                Toggle(
                    kind == .family ? "Von beiden Seiten bestätigt" : "Gegenseitige Verbindung",
                    isOn: $mutual
                )

                TextField("Notiz (optional)", text: $notes, axis: .vertical)

                Label(explanation, systemImage: kind == .family ? "house.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 470)
        .onAppear {
            if firstPersonID == nil {
                firstPersonID = sortedPeople.first?.id
            }
        }
        .onChange(of: firstPersonID) { _, newValue in
            if secondPersonID == newValue || !secondPersonChoices.contains(where: { $0.id == secondPersonID }) {
                secondPersonID = secondPersonChoices.first?.id
            }
        }
        .alert("Speichern nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var explanation: String {
        if kind == .family {
            return "Die gewählte Verwandtschaft gilt nur für dieses Personenpaar. Bei einer gegenseitigen Verbindung wird für die andere Richtung automatisch die passende Gegenrolle gespeichert."
        }
        return "Gegenseitige Freundschaften können automatisch zu einer Freundesgruppe zusammengefasst werden. Du kannst den Vorschlag anschließend manuell übernehmen und bearbeiten."
    }

    private func save() {
        guard let firstPersonID, let secondPersonID else { return }
        do {
            try store.setRelationshipPair(
                from: firstPersonID,
                to: secondPersonID,
                kind: kind,
                familyRole: kind == .family ? familyRole : nil,
                mutual: mutual,
                notes: notes,
                source: .manual,
                replacingKind: connection?.kind
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NetworkGroupEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let group: Group?

    @State private var name: String
    @State private var memberIDs: Set<UUID>
    @State private var errorMessage: String?

    init(group: Group?) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
        _memberIDs = State(initialValue: Set(group?.memberIDs ?? []))
    }

    private var sortedPeople: [Person] {
        store.data.people.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group == nil ? "Freundesgruppe hinzufügen" : "Freundesgruppe bearbeiten")
                        .font(.title2.weight(.bold))
                    if group?.status == .inferred {
                        Text("Beim Speichern wird der Vorschlag zu einer manuell gepflegten Gruppe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                    .disabled(trimmedName.isEmpty || memberIDs.count < 2)
            }
            .padding(20)
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                TextField("Gruppenname", text: $name)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Mitglieder")
                        .font(.headline)
                    Spacer()
                    Text("\(memberIDs.count) ausgewählt · mindestens 2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                List(sortedPeople) { person in
                    Button {
                        if memberIDs.contains(person.id) {
                            memberIDs.remove(person.id)
                        } else {
                            memberIDs.insert(person.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: memberIDs.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(memberIDs.contains(person.id) ? AppTheme.berry : .secondary)
                            Text(person.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)

                Label(
                    "Eine Gruppe ordnet Personen zusammen, erzeugt aber keine Familien- oder Freundschaftsverbindungen zwischen ihnen.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(width: 560, height: 590)
        .alert("Speichern nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        let selectedIDs = sortedPeople
            .filter { memberIDs.contains($0.id) }
            .map(\.id)
        let editedGroup = Group(
            id: group?.id ?? UUID(),
            name: trimmedName,
            memberIDs: selectedIDs,
            status: .manual,
            confidence: 1,
            explanation: group == nil ? "Manuell angelegte Gruppe." : "Manuell gepflegte Gruppe.",
            createdAt: group?.createdAt ?? Date()
        )

        do {
            if group == nil {
                try store.addGroup(editedGroup)
            } else {
                try store.updateGroup(editedGroup)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GraphPersonNode: View {
    @EnvironmentObject private var store: LibraryStore

    let person: Person
    let selected: Bool
    let action: () -> Void

    private var avatar: MediaItem? {
        guard let avatarID = person.avatarMediaID else { return nil }
        return store.data.media.first { $0.id == avatarID }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                LocalMediaView(media: avatar, cornerRadius: 31)
                    .frame(width: 62, height: 62)
                    .overlay {
                        Circle()
                            .stroke(selected ? AppTheme.plum : .white, lineWidth: selected ? 4 : 3)
                    }
                    .shadow(color: AppTheme.plum.opacity(0.2), radius: 9, y: 5)

                Text(person.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}
