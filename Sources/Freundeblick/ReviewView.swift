import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: LibraryStore

    @Binding var selectedPersonID: UUID?
    @Binding var section: AppSection?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    SectionTitle(
                        title: "Bitte prüfen",
                        subtitle: "Automatische Vorschläge werden nie still zu Tatsachen"
                    )
                    Spacer()
                    StatusPill(
                        text: "\(store.inferredGroups.count + pendingObservations.count) offen",
                        systemImage: "checkmark.seal",
                        tint: AppTheme.coralText
                    )
                }

                if store.inferredGroups.isEmpty && pendingObservations.isEmpty {
                    VStack {
                        EmptyArtwork(
                            systemImage: "checkmark.seal.fill",
                            title: "Alles geprüft",
                            message: "Neue Gruppenvorschläge und Medienbeobachtungen erscheinen hier mit ihrer Begründung."
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .surfaceCard()
                }

                ForEach(store.inferredGroups) { group in
                    ReviewGroupCard(group: group)
                }

                ForEach(pendingObservations) { observation in
                    ReviewObservationCard(observation: observation) {
                        selectedPersonID = observation.personID
                        section = .people
                    } confirm: {
                        changeObservation(observation, to: .confirmed)
                    } reject: {
                        changeObservation(observation, to: .archived)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 920)
        }
        .alert("Änderung nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var pendingObservations: [Observation] {
        store.data.observations.filter {
            $0.status == .likely || ($0.status == .unverified && $0.source == .inferred)
        }
    }

    private func changeObservation(_ observation: Observation, to status: ObservationStatus) {
        var updated = observation
        updated.status = status
        do {
            try store.updateObservation(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReviewGroupCard: View {
    @EnvironmentObject private var store: LibraryStore
    let group: Group

    @State private var originalGroup: Group
    @State private var proposedName: String
    @State private var errorMessage: String?

    init(group: Group) {
        self.group = group
        _originalGroup = State(initialValue: group)
        _proposedName = State(initialValue: group.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: "person.3.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.coralText)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mögliche Freundesgruppe")
                        .font(.headline)
                    Text(memberNames)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer()
                StatusPill(
                    text: "\(Int(group.confidence * 100)) % sicher",
                    systemImage: "sparkles",
                    tint: AppTheme.coralText
                )
            }

            Label(group.explanation, systemImage: "lightbulb.fill")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryInk)
                .padding(12)
                .background(AppTheme.apricot.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))

            HStack {
                TextField("Gruppenname", text: $proposedName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Button("Ablehnen", action: reject)
                    .buttonStyle(.bordered)
                Button("Bestätigen", action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
            }
        }
        .surfaceCard()
        .alert("Änderung nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var memberNames: String {
        group.memberIDs
            .compactMap { id in store.data.people.first { $0.id == id }?.name }
            .joined(separator: ", ")
    }

    private func confirm() {
        var updated = group
        updated.name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? group.name
            : proposedName
        updated.status = .manual
        updated.confidence = 1
        do {
            try store.updateGroup(updated, expecting: originalGroup)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reject() {
        var updated = group
        updated.status = .rejected
        do {
            try store.updateGroup(updated, expecting: originalGroup)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReviewObservationCard: View {
    @EnvironmentObject private var store: LibraryStore
    let observation: Observation
    let openPerson: () -> Void
    let confirm: () -> Void
    let reject: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title2)
                .foregroundStyle(AppTheme.berryText)
                .frame(width: 48, height: 48)
                .background(AppTheme.berry.opacity(0.11), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Button(personName, action: openPerson)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.berryText)
                Text(observation.value)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("Quelle: \(observation.source.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Ablehnen", action: reject)
                .buttonStyle(.bordered)
            Button("Bestätigen", action: confirm)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
        }
        .surfaceCard()
    }

    private var personName: String {
        store.data.people.first { $0.id == observation.personID }?.name ?? "Unbekannt"
    }
}
