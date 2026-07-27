import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PeopleSelection {
    static func reconciled(
        current: UUID?,
        previousIDs: [UUID],
        availableIDs: [UUID],
        preferNew: Bool = true
    ) -> UUID? {
        guard !availableIDs.isEmpty else { return nil }

        if preferNew {
            let previous = Set(previousIDs)
            if let inserted = availableIDs.first(where: { !previous.contains($0) }) {
                return inserted
            }
        }

        if let current, availableIDs.contains(current) {
            return current
        }
        return availableIDs.first
    }
}

struct PeopleView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selectedPersonID: UUID?

    @State private var searchText = ""
    @AppStorage("peopleListVisible") private var peopleListVisible = true

    var body: some View {
        SwiftUI.Group {
            if store.data.people.isEmpty {
                emptyLibrary
            } else {
                peopleBrowser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PeopleTabBackground()
                .ignoresSafeArea()
        }
        .onAppear {
            selectedPersonID = PeopleSelection.reconciled(
                current: selectedPersonID,
                previousIDs: allPersonIDs,
                availableIDs: allPersonIDs,
                preferNew: false
            )
        }
        .onChange(of: allPersonIDs) { previousIDs, availableIDs in
            let newSelection = PeopleSelection.reconciled(
                current: selectedPersonID,
                previousIDs: previousIDs,
                availableIDs: availableIDs
            )
            if newSelection != selectedPersonID {
                selectedPersonID = newSelection
            }
            if availableIDs.contains(where: { !Set(previousIDs).contains($0) }) {
                searchText = ""
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 0) {
            peopleHeader
            Divider()
            VStack {
                EmptyArtwork(
                    systemImage: "person.crop.circle.badge.plus",
                    title: "Erste Person anlegen",
                    message: "Name, Geburtstag, Wohnort, Charakter-Notizen und Interessen bilden das visuelle Profil."
                )
                Button("Person anlegen") {
                    store.presentNewPersonSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var peopleBrowser: some View {
        HStack(spacing: 0) {
            if peopleListVisible {
                VStack(spacing: 0) {
                    peopleHeader
                    inlineSearch

                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(filteredPeople) { person in
                                let isSelected = person.id == selectedPersonID
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        selectedPersonID = person.id
                                    }
                                } label: {
                                    PersonListRow(
                                        person: person,
                                        isSelected: isSelected
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(
                                    isSelected ? .isSelected : []
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .overlay {
                        if filteredPeople.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.berryText)
                                Text("Keine Treffer")
                                    .font(.callout.weight(.semibold))
                                Text("Versuche einen anderen Namen oder Ort.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(20)
                        }
                    }
                }
                .frame(width: 292)
                .background {
                    LinearGradient(
                        colors: [
                            AppTheme.plum.opacity(0.10),
                            AppTheme.berry.opacity(0.06),
                            AppTheme.apricot.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                Divider()
            }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            peopleListVisible.toggle()
                        }
                    } label: {
                        Label(
                            peopleListVisible ? "Personenliste ausblenden" : "Personenliste einblenden",
                            systemImage: "sidebar.left"
                        )
                    }
                    .buttonStyle(.borderless)
                    .help(
                        peopleListVisible
                            ? "Mehr Platz für das Profil"
                            : "Personenliste anzeigen"
                    )

                    if !peopleListVisible {
                        Text(selectedPerson?.name ?? "Personen")
                            .font(.headline)
                    }

                    Spacer()

                    if !peopleListVisible {
                        Button {
                            store.presentNewPersonSheet = true
                        } label: {
                            Label("Person hinzufügen", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.thinMaterial)

                Divider()

                personDetail
                    .frame(
                        minWidth: 430,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            }
        }
    }

    private var peopleHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "person.2.fill")
                .font(.callout.weight(.bold))
                .foregroundStyle(AppTheme.plumText)
                .frame(width: 34, height: 34)
                .background(
                    AppTheme.plum.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Personen")
                    .font(.headline.weight(.bold))
                Text("\(store.data.people.count) Profile")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.presentNewPersonSheet = true
            } label: {
                Label("Person hinzufügen", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.callout.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(
                        AppTheme.berry.opacity(0.13),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.berryText)
            .help("Person hinzufügen")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var inlineSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Name oder Ort", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Label("Suche löschen", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Color.primary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var personDetail: some View {
        if let selectedPerson {
            PersonDetailView(
                person: selectedPerson,
                selectedPersonID: $selectedPersonID
            )
            .id(selectedPerson.id)
        } else if filteredPeople.isEmpty {
            VStack {
                EmptyArtwork(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "Keine Treffer",
                    message: "Für „\(searchText)“ wurde keine Person gefunden."
                )
                Button("Suche löschen") {
                    searchText = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyArtwork(
                systemImage: "person.crop.circle",
                title: "Person auswählen",
                message: "Wähle links ein Profil aus."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var allPersonIDs: [UUID] {
        store.data.people
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(\.id)
    }

    private var filteredPeople: [Person] {
        store.data.people
            .filter { person in
                guard !searchText.isEmpty else { return true }
                return person.allNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
                    || (person.location?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedPerson: Person? {
        guard let selectedPersonID else { return nil }
        return store.data.people.first { $0.id == selectedPersonID }
    }
}

private struct PeopleTabBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.canvas(for: colorScheme)

            LinearGradient(
                colors: [
                    AppTheme.plum.opacity(0.13),
                    AppTheme.berry.opacity(0.10),
                    AppTheme.coral.opacity(0.08),
                    AppTheme.apricot.opacity(0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.coral.opacity(0.13))
                .frame(width: 440, height: 440)
                .blur(radius: 70)
                .offset(x: 330, y: -230)

            Circle()
                .fill(AppTheme.plum.opacity(0.11))
                .frame(width: 360, height: 360)
                .blur(radius: 65)
                .offset(x: -300, y: 260)

            Circle()
                .fill(AppTheme.apricot.opacity(0.13))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: 120, y: 330)
        }
        .accessibilityHidden(true)
    }
}

private struct PersonListRow: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.colorScheme) private var colorScheme

    let person: Person
    let isSelected: Bool

    @State private var isHovered = false

    private var avatar: MediaItem? {
        guard let avatarID = person.avatarMediaID else { return nil }
        return store.data.media.first { $0.id == avatarID }
    }

    var body: some View {
        HStack(spacing: 12) {
            LocalMediaView(media: avatar, cornerRadius: 24)
                .frame(width: 48, height: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            isSelected
                                ? AppTheme.apricot.opacity(0.92)
                                : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .shadow(
                    color: isSelected
                        ? AppTheme.berry.opacity(0.24)
                        : Color.black.opacity(0.08),
                    radius: isSelected ? 7 : 3,
                    y: 2
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(.callout.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                .font(isSelected ? .callout.weight(.bold) : .caption.weight(.semibold))
                .foregroundStyle(
                    isSelected
                        ? AppTheme.berryText
                        : Color.secondary.opacity(isHovered ? 0.9 : 0.48)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(rowBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(
                    isSelected
                        ? AppTheme.berry.opacity(colorScheme == .dark ? 0.76 : 0.52)
                        : Color.primary.opacity(isHovered ? 0.14 : 0.07),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(AppTheme.heroGradient)
                    .frame(width: 4)
                    .padding(.vertical, 11)
                    .offset(x: 1)
            }
        }
        .shadow(
            color: isSelected
                ? AppTheme.plum.opacity(colorScheme == .dark ? 0.30 : 0.14)
                : Color.clear,
            radius: 10,
            y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(person.name), \(subtitle)")
        .accessibilityValue(isSelected ? "Ausgewählt" : "")
    }

    private var subtitle: String {
        [ageText(person.birthday), person.location]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AppTheme.berry.opacity(colorScheme == .dark ? 0.30 : 0.15),
                        AppTheme.plum.opacity(colorScheme == .dark ? 0.25 : 0.11),
                        AppTheme.coral.opacity(colorScheme == .dark ? 0.14 : 0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            Color.primary.opacity(
                isHovered
                    ? (colorScheme == .dark ? 0.10 : 0.07)
                    : (colorScheme == .dark ? 0.055 : 0.035)
            )
        )
    }
}

private struct PersonDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    let person: Person
    @Binding var selectedPersonID: UUID?

    @State private var showingEditor = false
    @State private var showingAvatarPicker = false
    @State private var showingWebResearch = false
    @State private var importError: String?
    @State private var showingDeleteConfirmation = false

    private var avatar: MediaItem? {
        guard let id = person.avatarMediaID else { return nil }
        return store.data.media.first { $0.id == id }
    }

    private var observations: [Observation] {
        store.data.observations
            .filter { $0.personID == person.id && $0.status.isVisibleByDefault }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var media: [MediaItem] {
        store.data.media
            .filter { $0.personIDs.contains(person.id) }
            .sorted { $0.importedAt > $1.importedAt }
    }

    private var connectedPeople: [Person] {
        let ids = store.mutualFriendIDs(for: person.id)
        return store.data.people.filter { ids.contains($0.id) }
    }

    private var familyPeople: [Person] {
        let ids = Set(store.mutualFamilyIDs(for: person.id))
        return store.data.people
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var pendingFamilyPeople: [Person] {
        let ids = Set(store.pendingFamilyIDs(for: person.id))
        return store.data.people
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    profileHero
                    quickFacts
                    notesAndInterests
                    if !savedProfileDetails.isEmpty {
                        profileDetailsCard
                    }
                    profileLinks
                    relationships
                    styleObservations
                    memories
                }
                .padding(28)
                .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .sheet(isPresented: $showingEditor) {
            PersonEditorView(person: person)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingAvatarPicker) {
            ProfileImagePickerView(personID: person.id)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingWebResearch) {
            WebResearchView(person: person)
                .environmentObject(store)
        }
        .alert("Aktion nicht möglich", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog(
            "\(person.name) löschen?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Person endgültig löschen", role: .destructive) {
                deletePerson()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(
                "Das Profil, seine Beziehungen und Beobachtungen werden entfernt. "
                    + "Zugeordnete Mediendateien bleiben in der lokalen Bibliothek."
            )
        }
    }

    private var profileHero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 22) {
                heroAvatar(size: 132, cornerRadius: 32)
                heroInformation
                Spacer(minLength: 0)
            }
            .frame(minWidth: 600, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                heroAvatar(size: 100, cornerRadius: 26)
                heroInformation
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func heroAvatar(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Button {
            showingAvatarPicker = true
        } label: {
            LocalMediaView(media: avatar, cornerRadius: cornerRadius)
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.8), lineWidth: 3)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.plumText)
                        .frame(width: 30, height: 30)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                        .offset(x: 5, y: 5)
                }
                .shadow(color: AppTheme.plum.opacity(0.18), radius: 16, y: 8)
                .accessibilityLabel("Profilbild von \(person.name)")
                .accessibilityHint(
                    avatar == nil ? "Profilbild hinzufügen" : "Profilbild ändern"
                )
        }
        .buttonStyle(.plain)
        .help(avatar == nil ? "Profilbild hinzufügen" : "Profilbild ändern")
    }

    private var heroInformation: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(person.name)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            StatusPill(
                text: "von dir gepflegt",
                systemImage: "checkmark.circle.fill",
                tint: .white
            )

            if !person.aliases.isEmpty {
                Text("auch \(person.aliases.joined(separator: ", "))")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }

            FlowLayout(spacing: 9) {
                if let age = person.age() {
                    Label("\(age) Jahre", systemImage: "birthday.cake.fill")
                }
                if let location = person.location, !location.isEmpty {
                    Label(location, systemImage: "location.fill")
                }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))

            ViewThatFits(in: .horizontal) {
                HStack {
                    Button("Bearbeiten") { showingEditor = true }
                    Button(
                        avatar == nil ? "Profilbild hinzufügen" : "Profilbild ändern"
                    ) {
                        showingAvatarPicker = true
                    }
                    Button("Erinnerung hinzufügen", action: importMedia)
                    deleteMenu
                }

                VStack(alignment: .leading) {
                    Button("Bearbeiten") { showingEditor = true }
                    Button(
                        avatar == nil ? "Profilbild hinzufügen" : "Profilbild ändern"
                    ) {
                        showingAvatarPicker = true
                    }
                    Button("Erinnerung hinzufügen", action: importMedia)
                    deleteMenu
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    private var deleteMenu: some View {
        Menu {
            Button("Person löschen", role: .destructive) {
                showingDeleteConfirmation = true
            }
        } label: {
            Label("Mehr", systemImage: "ellipsis")
        }
    }

    private func deletePerson() {
        do {
            try store.deletePerson(id: person.id)
            selectedPersonID = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private var quickFacts: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
            ProfileFactCard(
                label: "Geburtstag",
                value: person.birthday.map { $0.formatted(date: .long, time: .omitted) } ?? "noch offen",
                systemImage: "birthday.cake"
            )
            ProfileFactCard(
                label: "Wohnort",
                value: person.location?.nilIfBlank ?? "noch offen",
                systemImage: "house.fill"
            )
            ProfileFactCard(
                label: "Verbindungen",
                value: "\(connectedPeople.count) Freunde · \(familyPeople.count) Familie",
                systemImage: "person.2.fill"
            )
            ProfileFactCard(
                label: "Erinnerungen",
                value: "\(media.count) Medien",
                systemImage: "photo.stack.fill"
            )
        }
    }

    @ViewBuilder
    private var notesAndInterests: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                temperamentCard
                interestsCard
            }
            .frame(minWidth: 600)

            VStack(alignment: .leading, spacing: 16) {
                temperamentCard
                interestsCard
            }
        }
    }

    private var temperamentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vom Gemüt", systemImage: "heart.text.square.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.plumText)

            if !person.temperamentTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(person.temperamentTags, id: \.self) { tag in
                        StatusPill(text: tag, systemImage: "person.fill", tint: AppTheme.plumText)
                    }
                }
            }

            Text(person.summary.nilIfBlank ?? "Noch keine persönliche Beschreibung. Charakter-Notizen werden nur aus deinen Angaben übernommen.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private var interestsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Interessen", systemImage: "star.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.coralText)
            if person.interests.isEmpty {
                Text("Noch keine Interessen gespeichert")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(person.interests, id: \.self) { interest in
                        StatusPill(text: interest, systemImage: "sparkles", tint: AppTheme.coralText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private var savedProfileDetails: [(key: String, values: [String])] {
        person.profileDetails
            .filter { !$0.value.isEmpty }
            .map { (key: $0.key, values: $0.value) }
            .sorted {
                ProfileSuggestionCatalog.displayLabel(for: $0.key)
                    .localizedCaseInsensitiveCompare(
                        ProfileSuggestionCatalog.displayLabel(for: $1.key)
                    ) == .orderedAscending
            }
    }

    private var profileDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Steckbrief", systemImage: "list.bullet.clipboard.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.berryText)
                Spacer()
                Text("\(savedProfileDetails.count) Angaben")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 10)],
                spacing: 10
            ) {
                ForEach(savedProfileDetails, id: \.key) { detail in
                    ProfileDetailValueCard(
                        detailKey: detail.key,
                        label: ProfileSuggestionCatalog.displayLabel(for: detail.key),
                        values: detail.values,
                        systemImage: ProfileSuggestionCatalog
                            .definition(for: detail.key)?.systemImage
                            ?? "square.and.pencil"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private var profileLinks: some View {
        VStack(alignment: .leading, spacing: 13) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    profileLinksTitle
                    Spacer()
                    researchButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    profileLinksTitle
                    researchButton
                }
            }

            if person.links.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "link.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.berryText)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Noch keine Links gespeichert")
                            .font(.callout.weight(.semibold))
                        Text("Füge Social-Media-Profile beim Bearbeiten hinzu oder starte eine Web-Recherche.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(padding: 14)
            } else {
                let confirmedLinks = person.links.filter(\.confirmed)
                let unconfirmedLinks = person.links.filter { !$0.confirmed }

                if !confirmedLinks.isEmpty {
                    linkCollection(
                        title: "Bestätigt",
                        systemImage: "checkmark.seal.fill",
                        tint: .green,
                        links: confirmedLinks
                    )
                }

                if !unconfirmedLinks.isEmpty {
                    linkCollection(
                        title: "Noch zu bestätigen",
                        systemImage: "questionmark.circle.fill",
                        tint: AppTheme.coral,
                        links: unconfirmedLinks
                    )
                }
            }
        }
    }

    private var profileLinksTitle: some View {
        SectionTitle(
            title: "Social Media & Webseiten",
            subtitle: "Gespeicherte Profile und öffentliche Seiten"
        )
    }

    private var researchButton: some View {
        Button {
            showingWebResearch = true
        } label: {
            Label("Im Web recherchieren", systemImage: "sparkle.magnifyingglass")
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.berry)
    }

    private func linkCollection(
        title: String,
        systemImage: String,
        tint: Color,
        links: [ProfileLink]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: 12)],
                spacing: 12
            ) {
                ForEach(links) { link in
                    ProfileLinkCard(link: link)
                }
            }
        }
    }

    private var relationships: some View {
        VStack(alignment: .leading, spacing: 13) {
            relationshipsTitle

            Label(
                "Familienverbindungen gelten immer nur zwischen zwei Personen. Andere Angehörige werden nicht automatisch miteinander verbunden.",
                systemImage: "info.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(padding: 12)

            relationshipCollection(
                title: "Familie · gegenseitig bestätigt",
                people: familyPeople,
                emptyMessage: "Noch keine gegenseitig bestätigte Familienverbindung.",
                systemImage: "house.and.flag.fill",
                tint: .blue,
                showsFamilyRole: true
            )

            if !pendingFamilyPeople.isEmpty {
                relationshipCollection(
                    title: "Familie · noch einseitig",
                    people: pendingFamilyPeople,
                    emptyMessage: "",
                    systemImage: "hourglass.circle.fill",
                    tint: AppTheme.coral,
                    showsFamilyRole: true
                )
            }

            relationshipCollection(
                title: "Freundschaften · gegenseitig bestätigt",
                people: connectedPeople,
                emptyMessage: "Noch keine gegenseitige Freundschaft gespeichert.",
                systemImage: "person.2.fill",
                tint: AppTheme.berryText,
                showsFamilyRole: false
            )
        }
    }

    @ViewBuilder
    private func relationshipCollection(
        title: String,
        people: [Person],
        emptyMessage: String,
        systemImage: String,
        tint: Color,
        showsFamilyRole: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)

            if people.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(padding: 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(people) { relatedPerson in
                            Button {
                                selectedPersonID = relatedPerson.id
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: systemImage)
                                        .font(.system(size: 34))
                                        .foregroundStyle(tint)
                                    Text(relatedPerson.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    if showsFamilyRole {
                                        Text(
                                            store.familyRole(
                                                from: person.id,
                                                to: relatedPerson.id
                                            )?.germanLabel ?? "Familienmitglied"
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }
                                }
                                .frame(width: 150, height: showsFamilyRole ? 104 : 90)
                                .surfaceCard(padding: 10)
                            }
                            .buttonStyle(.plain)
                            .help("Profil von \(relatedPerson.name) öffnen")
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var relationshipsTitle: some View {
        SectionTitle(
            title: "Beziehungen",
            subtitle: "Freundschaft und Familie getrennt und nachvollziehbar"
        )
    }

    @ViewBuilder
    private var styleObservations: some View {
        let style = observations.filter { $0.category == .clothing || $0.category == .appearance }
        if !style.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Stil", subtitle: "Mit Quelle und Sicherheit")
                ForEach(style) { observation in
                    HStack {
                        Image(systemName: "tshirt.fill")
                            .foregroundStyle(AppTheme.coralText)
                        Text(observation.value)
                            .font(.callout.weight(.semibold))
                        Spacer()
                        StatusPill(
                            text: "\(Int(observation.confidence * 100)) %",
                            systemImage: observation.status == .confirmed ? "checkmark.circle.fill" : "sparkles",
                            tint: observation.status == .confirmed ? .green : AppTheme.coral
                        )
                    }
                    .surfaceCard(padding: 14)
                }
            }
        }
    }

    private var memories: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    SectionTitle(title: "Erinnerungen", subtitle: "Fotos und Videos")
                    Spacer()
                    Button("Hinzufügen", action: importMedia)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Erinnerungen", subtitle: "Fotos und Videos")
                    Button("Hinzufügen", action: importMedia)
                }
            }

            if media.isEmpty {
                Text("Noch keine Medien für \(person.name).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(media) { item in
                            LocalMediaView(media: item)
                                .frame(width: 190, height: 132)
                        }
                    }
                }
            }
        }
    }

    private func importMedia() {
        let panel = NSOpenPanel()
        panel.title = "Medien für \(person.name)"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .movie, .video]

        guard panel.runModal() == .OK else { return }
        do {
            let imported = try store.importMedia(from: panel.urls, personIDs: [person.id])
            Task {
                for item in imported {
                    try? await store.analyzeMediaItem(id: item.id)
                }
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct ProfileImageCropCandidate: Identifiable {
    let id = UUID()
    let image: NSImage
    let sourceFilename: String
    let source: ProfileImageImportSource
    let capturedAt: Date?
}

private struct ProfileImagePickerView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let personID: UUID

    @State private var errorMessage: String?
    @State private var cropCandidate: ProfileImageCropCandidate?
    @State private var cameraKind: ProfileCameraKind?
    @State private var pendingCameraCropCandidate: ProfileImageCropCandidate?
    @State private var chooseFileAfterCamera = false
    @State private var closeAfterCrop = false

    private var person: Person? {
        store.person(id: personID)
    }

    private var images: [MediaItem] {
        store.media(for: personID).filter { $0.kind == .image }
    }

    private var selectedAvatarID: UUID? {
        person?.avatarMediaID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profilbild auswählen")
                        .font(.title2.weight(.bold))
                    Text(person.map { "Für \($0.name)" } ?? "Person nicht gefunden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Menu {
                    Button {
                        importProfileImage()
                    } label: {
                        Label("Bilddatei auswählen …", systemImage: "photo")
                    }
                    Divider()
                    Button {
                        cameraKind = .mac
                    } label: {
                        Label("Mac-Kamera", systemImage: "laptopcomputer")
                    }
                    Button {
                        cameraKind = .iPhone
                    } label: {
                        Label("iPhone-Kamera", systemImage: "iphone")
                    }
                } label: {
                    Label("Neues Profilbild", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
                .disabled(person == nil)
            }
            .padding(20)

            Divider()

            if images.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(AppTheme.berryText)
                    Text("Noch kein Bild vorhanden")
                        .font(.headline)
                    Text("Wähle eine Datei oder nimm ein Foto mit der Mac- oder iPhone-Kamera auf. Danach kannst du den Ausschnitt verschieben und vergrößern.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 470)
                    HStack(spacing: 10) {
                        sourceButton(
                            title: "Datei",
                            symbol: "photo",
                            action: importProfileImage
                        )
                        sourceButton(
                            title: "Mac-Kamera",
                            symbol: "laptopcomputer"
                        ) {
                            cameraKind = .mac
                        }
                        sourceButton(
                            title: "iPhone-Kamera",
                            symbol: "iphone"
                        ) {
                            cameraKind = .iPhone
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 170), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(images) { item in
                            Button {
                                select(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    LocalMediaView(media: item, cornerRadius: 18)
                                        .frame(height: 145)
                                        .overlay(alignment: .topTrailing) {
                                            if selectedAvatarID == item.id {
                                                Label(
                                                    "Aktuell",
                                                    systemImage: "checkmark.circle.fill"
                                                )
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 6)
                                                .background(AppTheme.berry, in: Capsule())
                                                .padding(8)
                                            }
                                        }

                                    Text(item.originalFilename)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                        .lineLimit(1)
                                    Text(
                                        selectedAvatarID == item.id
                                            ? "Aktuelles Bild neu zuschneiden"
                                            : "Zuschneiden und verwenden"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(
                                        selectedAvatarID == item.id
                                            ? AppTheme.berry
                                            : .secondary
                                    )
                                }
                                .padding(10)
                                .background(
                                    selectedAvatarID == item.id
                                        ? AppTheme.berry.opacity(0.1)
                                        : Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 22)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22)
                                        .stroke(
                                            selectedAvatarID == item.id
                                                ? AppTheme.berry
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Bild öffnen, zuschneiden und als Profilbild verwenden")
                        }
                    }
                    .padding(20)
                }

                if selectedAvatarID != nil {
                    Divider()
                    HStack {
                        Text("Vorhandene Erinnerungsbilder bleiben unverändert. Bei Datei oder Kamera wird nur der neue Zuschnitt gespeichert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Profilbild entfernen", role: .destructive) {
                            removeProfileImage()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 660, height: 540)
        .sheet(item: $cropCandidate, onDismiss: {
            if closeAfterCrop {
                closeAfterCrop = false
                dismiss()
            }
        }) { candidate in
            ProfileImageCropEditorView(
                image: candidate.image,
                sourceFilename: candidate.sourceFilename
            ) { pngData in
                try store.importCroppedProfileImage(
                    pngData: pngData,
                    originalFilename: candidate.sourceFilename,
                    for: personID,
                    source: candidate.source,
                    capturedAt: candidate.capturedAt
                )
                closeAfterCrop = true
            }
        }
        .sheet(item: $cameraKind, onDismiss: {
            if let pendingCameraCropCandidate {
                self.pendingCameraCropCandidate = nil
                cropCandidate = pendingCameraCropCandidate
            } else if chooseFileAfterCamera {
                chooseFileAfterCamera = false
                DispatchQueue.main.async {
                    importProfileImage()
                }
            }
        }) { kind in
            ProfileCameraCaptureView(
                initialKind: kind,
                onChooseFile: {
                    chooseFileAfterCamera = true
                }
            ) {
                data,
                capturedAt,
                sourceFilename in
                pendingCameraCropCandidate = try makeCropCandidate(
                    from: data,
                    sourceFilename: sourceFilename,
                    source: .camera,
                    capturedAt: capturedAt
                )
            }
        }
        .alert("Profilbild konnte nicht geändert werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func importProfileImage() {
        let panel = NSOpenPanel()
        panel.title = "Profilbild auswählen"
        panel.prompt = "Zuschneiden"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try prepareCrop(
                from: sourceURL,
                sourceFilename: sourceURL.lastPathComponent,
                source: .file
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ item: MediaItem) {
        do {
            try prepareCrop(
                from: store.mediaURL(for: item),
                sourceFilename: item.originalFilename,
                source: .existingMedia,
                capturedAt: item.capturedAt
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareCrop(
        from sourceURL: URL,
        sourceFilename: String,
        source: ProfileImageImportSource,
        capturedAt: Date? = nil
    ) throws {
        let values = try sourceURL.resourceValues(
            forKeys: [.fileSizeKey]
        )
        if let fileSize = values.fileSize,
           fileSize > ProfileImageSourceDecoder.maximumInputBytes {
            throw ProfileImageCropError.imageTooLarge
        }
        let imageData = try Data(contentsOf: sourceURL)
        cropCandidate = try makeCropCandidate(
            from: imageData,
            sourceFilename: sourceFilename,
            source: source,
            capturedAt: capturedAt
        )
    }

    private func makeCropCandidate(
        from imageData: Data,
        sourceFilename: String,
        source: ProfileImageImportSource,
        capturedAt: Date? = nil
    ) throws -> ProfileImageCropCandidate {
        ProfileImageCropCandidate(
            image: try ProfileImageSourceDecoder.image(from: imageData),
            sourceFilename: sourceFilename,
            source: source,
            capturedAt: capturedAt
        )
    }

    private func sourceButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(minWidth: 120)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func removeProfileImage() {
        do {
            try store.setAvatarMediaID(nil, for: personID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileLinkCard: View {
    @Environment(\.openURL) private var openURL

    let link: ProfileLink

    private var safeURL: URL? {
        guard let url = link.resolvedURL,
              PublicWebResearchService.isSafePublicPageURL(url)
        else {
            return nil
        }
        return url
    }

    var body: some View {
        Button {
            guard let url = safeURL else { return }
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: link.platform.symbolName)
                    .font(.title3)
                    .foregroundStyle(link.confirmed ? AppTheme.berry : AppTheme.coral)
                    .frame(width: 40, height: 40)
                    .background(
                        (link.confirmed ? AppTheme.berry : AppTheme.coral).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(link.displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .layoutPriority(1)

                    Text(link.platform.germanLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(link.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Image(systemName: safeURL == nil ? "exclamationmark.triangle.fill" : "arrow.up.right")
                    .foregroundStyle(safeURL == nil ? AppTheme.coral : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(safeURL == nil)
        .surfaceCard(padding: 13)
        .help(safeURL == nil ? "Nur öffentliche HTTPS-Adressen können geöffnet werden." : "Im Browser öffnen")
    }
}

private struct ProfileFactCard: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.berryText)
                .frame(width: 36, height: 36)
                .background(AppTheme.berry.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()
        }
        .surfaceCard(padding: 13)
    }
}

private struct ProfileDetailValueCard: View {
    let detailKey: String
    let label: String
    let values: [String]
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.berryText)
                .frame(width: 30, height: 30)
                .background(
                    AppTheme.berry.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if detailKey == "favoriteColors" {
                    ProfileColorValuesView(values: values)
                } else {
                    Text(values.joined(separator: " · "))
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            AppTheme.berry.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}

private enum PersonEditorPage: String, CaseIterable, Identifiable {
    case basics
    case personal
    case profile
    case links

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basics: "Grunddaten"
        case .personal: "Persönliches"
        case .profile: "Steckbrief"
        case .links: "Links"
        }
    }

    var subtitle: String {
        switch self {
        case .basics: "Name, Geburtstag und Beziehungen"
        case .personal: "Gemüt und Interessen"
        case .profile: "Vorlieben und Details"
        case .links: "Social Media und Webseiten"
        }
    }

    var systemImage: String {
        switch self {
        case .basics: "person.text.rectangle"
        case .personal: "heart.text.square.fill"
        case .profile: "list.bullet.clipboard.fill"
        case .links: "link.circle.fill"
        }
    }
}

struct PersonEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    private let existingPerson: Person?
    private let onSave: (Person) -> Void

    @State private var name: String
    @State private var aliases: [String]
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var location: String
    @State private var summary: String
    @State private var temperament: [String]
    @State private var interests: [String]
    @State private var profileDetails: [String: [String]]
    @State private var links: [ProfileLink]
    @State private var selectedPage: PersonEditorPage = .basics
    @State private var showingRelationshipEditor = false
    @State private var showingDiscardConfirmation = false
    @State private var errorMessage: String?

    init(
        person: Person? = nil,
        onSave: @escaping (Person) -> Void = { _ in }
    ) {
        existingPerson = person
        self.onSave = onSave
        _name = State(initialValue: person?.name ?? "")
        _aliases = State(initialValue: person?.aliases ?? [])
        _hasBirthday = State(initialValue: person?.birthday != nil)
        _birthday = State(initialValue: person?.birthday ?? Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date())
        _location = State(initialValue: person?.location ?? "")
        _summary = State(initialValue: person?.summary ?? "")
        _temperament = State(initialValue: person?.temperamentTags ?? [])
        _interests = State(initialValue: person?.interests ?? [])
        _profileDetails = State(initialValue: person?.profileDetails ?? [:])
        _links = State(initialValue: person?.links ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingPerson == nil ? "Neue Person" : "Profil bearbeiten")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Abbrechen", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Speichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || hasInvalidLink
                    )
            }
            .padding(20)

            if let validationMessage {
                HStack(spacing: 10) {
                    Label(
                        validationMessage.text,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.coralText)
                    Spacer()
                    Button("Fehler anzeigen") {
                        selectedPage = validationMessage.page
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(AppTheme.coral.opacity(0.10))
            }

            Divider()

            HStack(spacing: 0) {
                editorNavigation

                Divider()

                Form {
                    selectedPageContent
                }
                .formStyle(.grouped)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            minWidth: 820,
            idealWidth: 980,
            maxWidth: 1120,
            minHeight: 620,
            idealHeight: 780,
            maxHeight: 900
        )
        .sheet(isPresented: $showingRelationshipEditor) {
            if let existingPerson {
                RelationshipEditorView(person: existingPerson)
                    .environmentObject(store)
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
            Text(
                "Deine Änderungen am Steckbrief wurden noch nicht gespeichert."
            )
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    private var editorNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bereiche")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 16)

            ForEach(PersonEditorPage.allCases) { page in
                Button {
                    selectedPage = page
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: page.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(
                                selectedPage == page ? .white : AppTheme.berry
                            )
                            .frame(width: 30, height: 30)
                            .background(
                                selectedPage == page
                                    ? Color.white.opacity(0.18)
                                    : AppTheme.berry.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 9)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title)
                                .font(.callout.weight(.semibold))
                            Text(page.subtitle)
                                .font(.caption2)
                                .foregroundStyle(
                                    selectedPage == page
                                        ? Color.white
                                        : Color.secondary
                                )
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if pageSavedCount(page) > 0 {
                            Text("\(pageSavedCount(page))")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(
                                    selectedPage == page ? AppTheme.plum : AppTheme.berry
                                )
                                .frame(minWidth: 22, minHeight: 22)
                                .background(.white.opacity(0.92), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(selectedPage == page ? .white : AppTheme.ink)
                    .background(
                        selectedPage == page ? AppTheme.berry : Color.clear,
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Label("Profiländerungen werden erst mit „Speichern“ übernommen.", systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(14)
        }
        .padding(.horizontal, 8)
        .frame(width: 230)
        .frame(maxHeight: .infinity)
        .background(AppTheme.apricot.opacity(0.08))
    }

    @ViewBuilder
    private var selectedPageContent: some View {
        switch selectedPage {
        case .basics:
            Section("Grunddaten") {
                TextField("Name", text: $name)
                TokenSuggestionField(
                    title: "Spitznamen",
                    placeholder: "Spitzname eingeben",
                    suggestions: store.data.people.flatMap(\.aliases),
                    tint: AppTheme.berryText,
                    values: $aliases
                )
                LocationAutocompleteField(location: $location)
                Toggle("Geburtstag bekannt", isOn: $hasBirthday)
                if hasBirthday {
                    DatePicker(
                        "Geburtstag",
                        selection: $birthday,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }
            }

            Section("Beziehungen") {
                if existingPerson != nil {
                    if relationshipRows.isEmpty {
                        Text("Noch keine Verbindung gespeichert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(relationshipRows) { row in
                            HStack(spacing: 12) {
                                Image(systemName: relationshipSymbol(for: row.kind))
                                    .foregroundStyle(AppTheme.berryText)
                                    .frame(width: 26)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.otherPerson.name)
                                        .font(.callout.weight(.semibold))

                                    Text(relationshipDescription(for: row))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if row.mutual {
                                    Label("gegenseitig", systemImage: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    Button {
                        showingRelationshipEditor = true
                    } label: {
                        Label("Verbindung hinzufügen", systemImage: "link.badge.plus")
                    }
                    .disabled(store.data.people.count < 2)

                    if store.data.people.count < 2 {
                        Text("Lege zuerst mindestens eine weitere Person an.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Hier kannst du Familie, Freundschaft, Schule, Arbeit, Partnerschaft und weitere Verbindungen eintragen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label(
                        "Speichere die Person zuerst. Danach kannst du hier Beziehungen hinzufügen.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

        case .personal:
            Section("Persönliches") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "Geschlecht / Geschlechtsidentität",
                        systemImage: "person.crop.circle"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.berryText)

                    TokenSuggestionField(
                        title: "Geschlecht / Geschlechtsidentität",
                        placeholder: "z. B. Frau, Mann, nichtbinär oder eigene Angabe",
                        suggestions: ProfileSuggestionCatalog.genderIdentities
                            + store.data.people.flatMap {
                                $0.profileDetails["genderIdentity"] ?? []
                            },
                        tint: AppTheme.berryText,
                        values: personalDetailBinding("genderIdentity")
                    )
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "Sexuelle Orientierung",
                        systemImage: "heart.circle"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.coralText)

                    TokenSuggestionField(
                        title: "Sexuelle Orientierung",
                        placeholder: "z. B. hetero-, homo-, bi-, pansexuell oder eigene Angabe",
                        suggestions: ProfileSuggestionCatalog.sexualOrientations
                            + store.data.people.flatMap {
                                $0.profileDetails["sexualOrientation"] ?? []
                            },
                        tint: AppTheme.coral,
                        values: personalDetailBinding("sexualOrientation")
                    )
                }
                .padding(.vertical, 4)

                Text(
                    "Diese sensiblen Angaben sind freiwillig, bleiben lokal und "
                        + "werden von Freundeblick niemals automatisch abgeleitet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                TokenSuggestionField(
                    title: "Gemüt",
                    placeholder: "Gemüt eingeben, z. B. „ru“",
                    suggestions: ProfileSuggestionCatalog.temperament
                        + store.data.people.flatMap(\.temperamentTags),
                    tint: AppTheme.plumText,
                    values: $temperament
                )
                TokenSuggestionField(
                    title: "Interessen",
                    placeholder: "Interesse eingeben, z. B. „Mu“",
                    suggestions: ProfileSuggestionCatalog.interests
                        + store.data.people.flatMap(\.interests),
                    tint: AppTheme.coral,
                    values: $interests
                )
                TextField("Kurze Beschreibung", text: $summary, axis: .vertical)
                    .lineLimit(3...10)
                Text("Charakterangaben stammen von dir. Die App leitet sie nicht aus Gesicht, Kleidung oder Stimme ab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .profile:
            Section("Steckbrief") {
                ProfileDetailsEditor(details: $profileDetails)
            }

        case .links:
            Section("Social Media & Webseiten") {
                if links.isEmpty {
                    Text("Noch keine Links. Du kannst Profile und Webseiten einzeln hinzufügen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach($links) { $link in
                    ProfileLinkEditorRow(link: $link) { linkID in
                        links.removeAll { $0.id == linkID }
                    }
                }

                Button {
                    links.append(
                        ProfileLink(
                            platform: .website,
                            url: "",
                            confirmed: true
                        )
                    )
                } label: {
                    Label("Link hinzufügen", systemImage: "plus.circle.fill")
                }

                if hasInvalidLink {
                    Label(
                        "Jeder Link benötigt eine öffentliche HTTPS-Adresse.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.coralText)
                } else {
                    Text("Manuell eingetragene Links sind standardmäßig bestätigt. Treffer aus einer Web-Recherche kannst du vor dem Bestätigen prüfen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pageSavedCount(_ page: PersonEditorPage) -> Int {
        switch page {
        case .basics:
            return [
                name.nilIfBlank != nil,
                !aliases.isEmpty,
                location.nilIfBlank != nil,
                hasBirthday,
            ].filter { $0 }.count + relationshipRows.count
        case .personal:
            return [
                !(profileDetails["genderIdentity"] ?? []).isEmpty,
                !(profileDetails["sexualOrientation"] ?? []).isEmpty,
                !temperament.isEmpty,
                !interests.isEmpty,
                summary.nilIfBlank != nil,
            ].filter { $0 }.count
        case .profile:
            return profileDetails.filter {
                !["genderIdentity", "sexualOrientation"].contains($0.key)
                    && !$0.value.isEmpty
            }.count
        case .links:
            return links.filter { $0.url.nilIfBlank != nil }.count
        }
    }

    private func save() {
        let cleanedLinks = links.map { link in
            ProfileLink(
                id: link.id,
                kind: link.platform.kind,
                platform: link.platform,
                title: link.title,
                url: link.url,
                handle: link.handle,
                confirmed: link.confirmed,
                createdAt: link.createdAt
            )
        }
        let person = Person(
            id: existingPerson?.id ?? UUID(),
            name: name,
            aliases: aliases,
            birthday: hasBirthday ? birthday : nil,
            location: location.nilIfBlank,
            summary: summary,
            temperamentTags: temperament,
            interests: interests,
            profileDetails: profileDetails,
            links: cleanedLinks,
            avatarMediaID: existingPerson?.avatarMediaID,
            createdAt: existingPerson?.createdAt ?? Date()
        )

        do {
            if existingPerson == nil {
                try store.addPerson(person)
            } else if let existingPerson {
                try store.updatePerson(person, expecting: existingPerson)
            }
            onSave(person)
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

    private var hasUnsavedChanges: Bool {
        name != (existingPerson?.name ?? "")
            || aliases != (existingPerson?.aliases ?? [])
            || (hasBirthday ? birthday : nil) != existingPerson?.birthday
            || location != (existingPerson?.location ?? "")
            || summary != (existingPerson?.summary ?? "")
            || temperament != (existingPerson?.temperamentTags ?? [])
            || interests != (existingPerson?.interests ?? [])
            || profileDetails != (existingPerson?.profileDetails ?? [:])
            || links != (existingPerson?.links ?? [])
    }

    private var hasInvalidLink: Bool {
        links.contains { link in
            guard link.url.nilIfBlank != nil,
                  let url = link.resolvedURL
            else {
                return true
            }
            return !PublicWebResearchService.isSafePublicPageURL(url)
        }
    }

    private var validationMessage: (text: String, page: PersonEditorPage)? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("Bitte gib einen Namen ein.", .basics)
        }
        if hasInvalidLink {
            return (
                "Mindestens ein öffentlicher Link ist unvollständig oder unsicher.",
                .links
            )
        }
        return nil
    }

    private func personalDetailBinding(_ key: String) -> Binding<[String]> {
        Binding(
            get: { profileDetails[key] ?? [] },
            set: { values in
                if values.isEmpty {
                    profileDetails.removeValue(forKey: key)
                } else {
                    profileDetails[key] = values
                }
            }
        )
    }

    private var relationshipRows: [BasicRelationshipRow] {
        guard let existingPerson else { return [] }

        let relevantClaims = store.data.relationshipClaims.filter { claim in
            claim.status.supportsInference
                && (claim.fromPersonID == existingPerson.id
                    || claim.toPersonID == existingPerson.id)
        }
        var seenKeys = Set<String>()
        var rows: [BasicRelationshipRow] = []

        for claim in relevantClaims {
            let otherPersonID = claim.fromPersonID == existingPerson.id
                ? claim.toPersonID
                : claim.fromPersonID
            let key = "\(otherPersonID.uuidString)|\(claim.kind.rawValue)"
            guard !seenKeys.contains(key),
                  let otherPerson = store.data.people.first(where: { $0.id == otherPersonID })
            else {
                continue
            }

            let outgoing = relevantClaims.first {
                $0.fromPersonID == existingPerson.id
                    && $0.toPersonID == otherPersonID
                    && $0.kind == claim.kind
            }
            let incoming = relevantClaims.first {
                $0.fromPersonID == otherPersonID
                    && $0.toPersonID == existingPerson.id
                    && $0.kind == claim.kind
            }
            let familyRole = outgoing?.familyRole ?? incoming?.familyRole?.inverse

            rows.append(
                BasicRelationshipRow(
                    otherPerson: otherPerson,
                    kind: claim.kind,
                    familyRole: familyRole,
                    mutual: outgoing != nil && incoming != nil
                )
            )
            seenKeys.insert(key)
        }

        return rows.sorted {
            if $0.kind.germanLabel == $1.kind.germanLabel {
                return $0.otherPerson.name.localizedCaseInsensitiveCompare(
                    $1.otherPerson.name
                ) == .orderedAscending
            }
            return $0.kind.germanLabel.localizedCaseInsensitiveCompare(
                $1.kind.germanLabel
            ) == .orderedAscending
        }
    }

    private func relationshipDescription(for row: BasicRelationshipRow) -> String {
        guard row.kind == .family, let familyRole = row.familyRole else {
            return row.kind.germanLabel
        }
        return "\(row.kind.germanLabel) · \(familyRole.germanLabel)"
    }

    private func relationshipSymbol(for kind: RelationshipKind) -> String {
        switch kind {
        case .friendship: "person.2.fill"
        case .family: "house.and.flag.fill"
        case .romantic: "heart.fill"
        case .school: "graduationcap.fill"
        case .work: "briefcase.fill"
        case .acquaintance: "person.crop.circle.badge.checkmark"
        case .other: "link"
        }
    }
}

private struct BasicRelationshipRow: Identifiable {
    let otherPerson: Person
    let kind: RelationshipKind
    let familyRole: FamilyRelationshipRole?
    let mutual: Bool

    var id: String {
        "\(otherPerson.id.uuidString)|\(kind.rawValue)"
    }
}

private struct ProfileLinkEditorRow: View {
    @Binding var link: ProfileLink
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(link.platform.germanLabel, systemImage: link.platform.symbolName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.plumText)
                Spacer()
                Toggle("Bestätigt", isOn: $link.confirmed)
                    .toggleStyle(.checkbox)
                Button(role: .destructive) {
                    let linkID = link.id
                    onDelete(linkID)
                } label: {
                    Label("Löschen", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Link löschen")
            }

            Picker(
                "Plattform",
                selection: Binding(
                    get: { link.platform },
                    set: { platform in
                        link.platform = platform
                        link.kind = platform.kind
                    }
                )
            ) {
                ForEach(ProfileLinkPlatform.allCases, id: \.self) { platform in
                    Label(platform.germanLabel, systemImage: platform.symbolName)
                        .tag(platform)
                }
            }

            HStack {
                TextField("Titel, z. B. Foto-Profil", text: $link.title)
                TextField("@name (optional)", text: $link.handle)
            }

            TextField("Webadresse, z. B. https://instagram.com/name", text: $link.url)
                .textContentType(.URL)

            if link.url.nilIfBlank != nil,
               link.resolvedURL.map(PublicWebResearchService.isSafePublicPageURL) != true {
                Label("Bitte eine öffentliche HTTPS-Adresse verwenden.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.coralText)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct RelationshipEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let person: Person

    @State private var otherPersonID: UUID?
    @State private var kind: RelationshipKind = .friendship
    @State private var familyRole: FamilyRelationshipRole = .familyMember
    @State private var mutual = true
    @State private var notes = ""
    @State private var relationshipBaseline: [RelationshipClaim]?
    @State private var errorMessage: String?

    private var otherPeople: [Person] {
        store.data.people.filter { $0.id != person.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Verbindung hinzufügen")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                    .disabled(otherPersonID == nil)
            }
            .padding(20)
            Divider()

            Form {
                Picker("Andere Person", selection: $otherPersonID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(otherPeople) { candidate in
                        Text(candidate.name).tag(Optional(candidate.id))
                    }
                }

                Picker("Beziehung", selection: $kind) {
                    ForEach(RelationshipKind.allCases, id: \.self) { kind in
                        Text(kind.germanLabel).tag(kind)
                    }
                }

                if kind == .family {
                    Picker("Verwandtschaft", selection: $familyRole) {
                        ForEach(FamilyRelationshipRole.allCases, id: \.self) { role in
                            Text(role.germanLabel).tag(role)
                        }
                    }
                }

                Toggle(
                    kind == .family
                        ? "Von beiden Personen bestätigt"
                        : "Gegenseitig angegeben",
                    isOn: $mutual
                )
                TextField("Notiz (optional)", text: $notes, axis: .vertical)

                Text(relationshipExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 400)
        .onChange(of: kind) { _, newKind in
            if newKind == .family {
                mutual = false
            }
        }
        .onAppear {
            if relationshipBaseline == nil {
                relationshipBaseline = store.data.relationshipClaims
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

    private var relationshipExplanation: String {
        if kind == .family {
            return "Eine einseitige Familienangabe bleibt zunächst offen. Du kannst die Gegenangabe später im anderen Profil eintragen oder „Von beiden Personen bestätigt“ aktivieren. Die Verbindung gilt nur für dieses Paar; andere Angehörige werden nicht automatisch verbunden."
        }
        return "Bei einer gegenseitigen Verbindung speichert Freundeblick zwei gerichtete Aussagen. So bleibt sichtbar, wer wen angegeben hat."
    }

    private func save() {
        guard let otherPersonID else { return }
        let expectedClaims = (relationshipBaseline ?? []).filter { claim in
            let isSamePair =
                (claim.fromPersonID == person.id
                    && claim.toPersonID == otherPersonID)
                || (claim.fromPersonID == otherPersonID
                    && claim.toPersonID == person.id)
            return isSamePair && claim.kind == kind
        }
        do {
            guard expectedClaims.isEmpty else {
                throw LibraryStoreError.relationshipKindConflict
            }
            try store.setRelationshipPair(
                from: person.id,
                to: otherPersonID,
                kind: kind,
                familyRole: kind == .family ? familyRole : nil,
                mutual: mutual,
                notes: notes,
                source: .personStatement,
                expecting: expectedClaims
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
