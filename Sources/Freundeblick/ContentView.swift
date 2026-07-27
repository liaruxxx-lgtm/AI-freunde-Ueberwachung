import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @State private var section: AppSection? = .overview
    @State private var selectedPersonID: UUID?
    @State private var globalQuestion = ""

    var body: some View {
        SwiftUI.Group {
            if store.isLibraryAvailable {
                libraryContent
            } else {
                LibraryUnavailableView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: newPersonSheetBinding) {
            PersonEditorView(onSave: { person in
                selectedPersonID = person.id
            })
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active,
               FileManager.default.fileExists(atPath: store.databaseURL.path) {
                try? store.reload()
            }
        }
    }

    private var libraryContent: some View {
        NavigationSplitView {
            Sidebar(selection: $section, selectedPersonID: $selectedPersonID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 290)
        } detail: {
            ZStack {
                AppTheme.canvas(for: colorScheme)
                    .ignoresSafeArea()

                detail
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(AppTheme.berryText)
                        TextField("Frag: Wer ist Leni?", text: $globalQuestion)
                            .textFieldStyle(.plain)
                            .frame(minWidth: 180, idealWidth: 280, maxWidth: 280)
                            .onSubmit(openQuestion)
                        if !globalQuestion.isEmpty {
                            Button(action: openQuestion) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(AppTheme.berryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                }

                ToolbarItemGroup {
                    Button {
                        store.presentNewPersonSheet = true
                    } label: {
                        Label("Neue Person", systemImage: "person.badge.plus")
                    }
                    .help("Neue Person anlegen")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var newPersonSheetBinding: Binding<Bool> {
        Binding(
            get: {
                store.isLibraryAvailable && store.presentNewPersonSheet
            },
            set: {
                store.presentNewPersonSheet = $0
            }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .overview {
        case .overview:
            DashboardView(
                selectedPersonID: $selectedPersonID,
                section: $section,
                question: $globalQuestion
            )
        case .people:
            PeopleView(selectedPersonID: $selectedPersonID)
        case .compare:
            CompareView(
                selectedPersonID: $selectedPersonID,
                section: $section
            )
        case .network:
            NetworkView(selectedPersonID: $selectedPersonID, section: $section)
        case .media:
            MediaGalleryView()
        case .review:
            ReviewView(selectedPersonID: $selectedPersonID, section: $section)
        case .assistant:
            AssistantAccessView(initialQuestion: globalQuestion, selectedPersonID: $selectedPersonID, section: $section)
        }
    }

    private func openQuestion() {
        guard !globalQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        section = .assistant
    }
}

private struct LibraryUnavailableView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingRestoreConfirmation = false
    @State private var recoveryError: String?

    var body: some View {
        ZStack {
            AppTheme.canvas(for: colorScheme)
                .ignoresSafeArea()

            Circle()
                .fill(AppTheme.coral.opacity(0.13))
                .frame(width: 460, height: 460)
                .blur(radius: 2)
                .offset(x: 320, y: -230)

            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(AppTheme.heroGradient)
                    .frame(width: 86, height: 86)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25))

                VStack(spacing: 8) {
                    Text("Bibliothek konnte nicht geladen werden")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(
                        "Zum Schutz deiner Personen und Erinnerungen sind Änderungen "
                            + "gesperrt. Die vorhandene Datei wird nicht überschrieben."
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Fehler beim Laden", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.coralText)
                    Text(store.lastError ?? "Unbekannter Fehler")
                        .font(.callout)
                        .textSelection(.enabled)
                    Text(store.databaseURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 660, alignment: .leading)
                .surfaceCard(padding: 16)

                HStack(spacing: 12) {
                    Button(action: retryLoading) {
                        Label("Erneut laden", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)

                    if store.hasDatabaseBackup {
                        Button {
                            showingRestoreConfirmation = true
                        } label: {
                            Label(
                                "Sicherung wiederherstellen",
                                systemImage: "clock.arrow.circlepath"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(action: revealDataFolder) {
                        Label("Datenordner zeigen", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(42)
        }
        .confirmationDialog(
            "Letzte Sicherung wiederherstellen?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sicherung wiederherstellen", role: .destructive) {
                restoreBackup()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(
                "Die nicht lesbare Datei bleibt als separate Sicherheitskopie erhalten. "
                    + "Danach wird friends.backup.json geladen."
            )
        }
        .alert("Wiederherstellung nicht möglich", isPresented: Binding(
            get: { recoveryError != nil },
            set: { if !$0 { recoveryError = nil } }
        )) {
            Button("OK", role: .cancel) {
                recoveryError = nil
            }
        } message: {
            Text(recoveryError ?? "")
        }
    }

    private func retryLoading() {
        do {
            try store.reload()
        } catch {
            recoveryError = error.localizedDescription
        }
    }

    private func restoreBackup() {
        do {
            try store.restoreDatabaseBackup()
        } catch {
            recoveryError = error.localizedDescription
        }
    }

    private func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.databaseURL])
    }
}
