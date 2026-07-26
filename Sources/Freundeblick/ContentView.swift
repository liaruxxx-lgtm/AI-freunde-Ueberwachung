import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var section: AppSection? = .overview
    @State private var selectedPersonID: UUID?
    @State private var globalQuestion = ""

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $section, selectedPersonID: $selectedPersonID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 290)
        } detail: {
            ZStack {
                AppTheme.cream
                    .opacity(0.72)
                    .ignoresSafeArea()

                detail
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(AppTheme.berry)
                        TextField("Frag: Wer ist Leni?", text: $globalQuestion)
                            .textFieldStyle(.plain)
                            .frame(minWidth: 180, idealWidth: 280, maxWidth: 280)
                            .onSubmit(openQuestion)
                        if !globalQuestion.isEmpty {
                            Button(action: openQuestion) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(AppTheme.berry)
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
        .sheet(isPresented: $store.presentNewPersonSheet) {
            PersonEditorView(onSave: { person in
                selectedPersonID = person.id
            })
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                try? store.reload()
            }
        }
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
