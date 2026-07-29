import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore

    @AppStorage("allowMediaPreviews") private var allowMediaPreviews = true

    var body: some View {
        Form {
            Section("Bibliothek") {
                LabeledContent("Datenbank", value: LibraryPaths.databaseURL.path)
                LabeledContent("Medienordner", value: LibraryPaths.mediaDirectory.path)
                LabeledContent("Personen", value: "\(store.data.people.count)")
            }

            Section("Steckbrief-Eingabe") {
                Label("Über 50 freiwillige Angaben sind in ausklappbare Bereiche sortiert.", systemImage: "list.bullet.clipboard.fill")
                Label("Automatische Vorschläge erscheinen ab drei Zeichen; die manuelle Auswahlliste lässt sich jederzeit öffnen.", systemImage: "text.badge.checkmark")
                Label("Eigene Rubriken lassen sich jederzeit hinzufügen.", systemImage: "plus.square.on.square")
            }

            Section("Medien in der App") {
                Toggle("Medienvorschauen erlauben", isOn: $allowMediaPreviews)
                Text("Wenn die Vorschau aus ist, bleiben Bilder und Videos gespeichert, werden aber in Freundeblick verdeckt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Profilbilder vom iPhone") {
                Label("Vorhandene Fotos lassen sich von einem per USB verbundenen iPhone auswählen.", systemImage: "iphone")
                Label("Das iPhone muss entsperrt sein und diesem Mac vertrauen.", systemImage: "lock.open.fill")
                Label("Gespeichert wird nur der von dir bestätigte quadratische Zuschnitt.", systemImage: "crop")
                Text("Der iPhone-Import ist von der Continuity-Camera-Aufnahme getrennt. Für die Auswahl zeigt Freundeblick Vorschaubilder und grundlegende Metadaten an. Das Original bleibt unverändert auf dem iPhone; dauerhaft gespeichert wird nur dein Zuschnitt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Codex-Zugriff") {
                Label("Datenbankänderungen über Codex sind erlaubt.", systemImage: "pencil.and.list.clipboard")
                Label("Löschzugriffe und Originalmedien bleiben gesperrt.", systemImage: "checkmark.shield.fill")

                Text("Codex kann Profile, öffentliche Links, Beziehungen und Beobachtungen atomar speichern. Neue Beobachtungen werden standardmäßig als unbestätigt markiert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Automatische Beobachtungen") {
                Label("Gruppen werden als Vorschläge erkannt und müssen bestätigt werden.", systemImage: "person.3.fill")
                Label("Persönlichkeit wird nicht aus Fotos oder Stimme abgeleitet.", systemImage: "brain.head.profile")
                Label("Kleidungs-Tags bleiben mit ihren Belegmedien verknüpft.", systemImage: "tshirt.fill")
            }

            Section("Öffentliche Web-Recherche") {
                Label("Eine Suche startet nur nach einem ausdrücklichen Klick.", systemImage: "hand.tap.fill")
                Label("Der genaue Suchtext ist vor dem Senden sichtbar.", systemImage: "text.magnifyingglass")
                Label("Notizen, Fotos und Beziehungsdaten werden nicht automatisch ergänzt.", systemImage: "hand.raised.fill")
                Label("Wikipedia und DuckDuckGo erhalten beim Suchen technisch die IP-Adresse.", systemImage: "network")
                Label("Treffer werden erst nach deiner Zuordnung als Link gespeichert.", systemImage: "checkmark.shield.fill")

                Text("Für Minderjährige bleibt die automatische Namenssuche aus; bei unbekanntem Geburtstag ist eine Volljährigkeitsbestätigung nötig. Bekannte direkte Personensuchlinks werden blockiert, aber Treffer lassen sich nicht vollständig klassifizieren.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ortsvorschläge & Karte") {
                Label("Ortsvorschläge erscheinen ab drei eingegebenen Zeichen.", systemImage: "text.magnifyingglass")
                Label("Die Karte erlaubt eine Auswahl per Suche oder Mausklick.", systemImage: "map.fill")
                Text("Ortsvorschläge, Kartendaten und die Rückübersetzung eines Kartenpunkts werden von Apple Karten bereitgestellt. Der Suchtext beziehungsweise der angeklickte Kartenpunkt wird dafür an Apple gesendet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
