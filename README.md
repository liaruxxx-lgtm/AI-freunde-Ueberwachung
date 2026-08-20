# Freundeblick

> [!WARNING]
> **Projektstatus:** Dieses Projekt befindet sich in aktiver Entwicklung, ist noch
> nicht fertiggestellt und kann unvollständige oder fehlerhafte Funktionen
> enthalten. Änderungen können jederzeit und ohne Vorankündigung erfolgen.
>
> **Haftungshinweis:** Nutzung, Installation und Weiterverwendung erfolgen auf
> eigene Gefahr. Soweit gesetzlich zulässig, wird keine Haftung für unmittelbare
> oder mittelbare Schäden, Datenverluste, Fehlfunktionen, Sicherheitsprobleme
> oder sonstige Folgen übernommen. Es gibt keine Garantie für Funktionsfähigkeit,
> Richtigkeit, Sicherheit oder Eignung für einen bestimmten Zweck.

Freundeblick ist eine native, lokale macOS-App für visuelle Personenprofile, Erinnerungen und Beziehungsnetze. Sie startet leer und speichert alle persönlichen Daten im Ordner `FreundeblickData`, der von Git ausgeschlossen ist.

## Bereits nutzbar

- Personen mit Name, Spitznamen, Geburtstag, Wohnort, Kurzbeschreibung, Charakter-Tags und Interessen
- auswählbare Profilbilder: Datei oder vorhandenes Personenfoto verwenden, über Mac-/Continuity-Kamera aufnehmen oder ein vorhandenes Foto direkt von einem per USB verbundenen iPhone importieren
- großzügiges Bearbeiten-Fenster mit fester Bereichsnavigation; im Steckbrief bleibt für bessere Übersicht nur eine Kategorie gleichzeitig geöffnet
- farbiger Personenbereich mit weichem Verlauf, dezenten Lichtflächen und klar hervorgehobener Profilauswahl
- großer ausklappbarer Steckbrief mit über 50 freiwilligen Feldern von Lieblingsfarbe und Essen bis Automarke, Gewohnheiten, Träumen und spielerischen Fragen
- frei benennbare eigene Steckbrief-Rubriken für alles, was nicht vorgegeben ist
- Vergleichsansicht für zwei bis vier Personen mit farbigem Radar, Balkendiagrammen, Überschneidungen und Profilkarten
- paarweise Familienverbindungen mit Verwandtschaftsart, offener Gegenbestätigung und ohne automatische Verknüpfung weiterer Angehöriger
- Wohnort-Autovervollständigung ab drei Zeichen sowie Auswahl über Apple Karten
- jederzeit manuell ausklappbare Vorschlagslisten sowie automatische Präfixvervollständigung ab drei Zeichen für Gemüt, Interessen, Spitznamen und Medien-Tags
- Social-Media-Profile und Webseiten mit Plattform, Handle und Bestätigungsstatus
- gerichtete Beziehungsaussagen: Es bleibt nachvollziehbar, wer wen als Freund bezeichnet hat
- visueller Netzwerkgraph mit Beziehungstypen und unterschiedlicher Darstellung für ein- und gegenseitige Angaben
- automatisch vorgeschlagene Freundesgruppen ab drei vollständig gegenseitig verbundenen Personen
- prüfbare Vorschläge: Gruppen und Medienbeobachtungen können bestätigt oder abgelehnt werden
- Import von Fotos und Videos in einen lokalen Medienordner
- lokale Apple-Vision-Analyse von Bildern und drei repräsentativen Videoframes
- Kleidungsbegriffe werden nur vorgeschlagen; erst eine Nutzerauswahl macht daraus einen bestätigten Tag
- Stil-Aussagen erst ab mindestens drei verschiedenen bestätigten Medien
- ausdrücklich gestartete Web-Recherche mit zwei Wegen: ausgewählte Steckbrief-Hinweise wie Sport + Ort zu möglichen Vereinen, Webseiten und öffentlichen Social-Media-Quellen kombinieren oder eine Person gezielt suchen
- Hinweis-Treffer werden nach Quelle gesammelt, klar als Vermutung markiert und lassen sich erst nach eigener Prüfung als bearbeitete Angabe und Quellenlink in den Steckbrief übernehmen
- natürliches deutsches Fragefeld, unter anderem für „Wer ist …?“, Alter, Wohnort, Freunde, Gruppen, Stil, Medien und öffentliche Links
- der Auftrag „Recherchiere im Internet nach …“ öffnet direkt die kontrollierte Recherche
- lokale MCP-Schnittstelle, über die Codex Informationen strukturiert abfragen und ausgewählte Daten sicher speichern kann

## Datenschutzregeln

- Die Bibliothek bleibt lokal; für die optionale Web-Recherche ist kein API-Schlüssel nötig.
- Beim iPhone-Import werden Vorschaubilder und grundlegende Metadaten für die Auswahl angezeigt. Die vollständigen Originaldaten werden nur für das ausdrücklich ausgewählte Foto geladen; dauerhaft gespeichert wird ausschließlich der bestätigte quadratische PNG-Zuschnitt.
- Ortsvorschläge und Kartenauswahl verwenden Apple Karten; der eingegebene Ortssuchtext beziehungsweise ein angeklickter Kartenpunkt wird dafür an Apple gesendet.
- Erst „Suche starten“ sendet den vorher sichtbaren Suchtext an Wikipedia und DuckDuckGo.
- Standardmäßig werden nur der Name und ein ausdrücklich eingegebener Suchzusatz gesendet. Der gespeicherte Ortswert wird nur nach Aktivieren des Schalters ergänzt; beide Dienste erhalten technisch die IP-Adresse.
- DuckDuckGo läuft in einem nicht dauerhaften Webfenster ohne JavaScript. Externe Treffer werden vor dem Öffnen angehalten.
- Treffer werden nie automatisch einer Person zugeordnet oder als Tatsache gespeichert. Der Nutzer muss den Link ausdrücklich bestätigen.
- Für Minderjährige ist die automatische Namenssuche deaktiviert. Bei unbekanntem Geburtstag muss die Volljährigkeit ausdrücklich bestätigt werden; bei nur einem Vornamen ist zusätzlich ein Identitätshinweis erforderlich.
- Direkte private IP-Ziele sowie bekannte Datenbroker- und Personensuchdienste werden blockiert. Suchtreffer, DNS-Aliase und Weiterleitungen lassen sich nicht vollständig klassifizieren.
- Originalmedien werden nicht über MCP ausgegeben.
- Gesichtszuteilungen und biometrische Merkmale sind im MVP bewusst nicht enthalten.
- Charakter oder Persönlichkeit werden niemals aus Gesicht, Stimme oder Kleidung abgeleitet. Solche Angaben stammen ausschließlich von dir.
- Automatische Ergebnisse bleiben Vorschläge mit Quelle und Sicherheit.
- `FreundeblickData/*` ist in `.gitignore` gesperrt.

## App starten

Das fertig gebaute und nach dem Entpacken signaturgeprüfte App-Paket liegt hier:

```text
dist/Freundeblick.zip
```

Entpacke die ZIP-Datei außerhalb dieses synchronisierten Projektordners und verschiebe `Freundeblick.app` am besten in den Programme-Ordner. Der Build enthält den absoluten Pfad zur gemeinsamen lokalen Datenbibliothek, damit App und Codex auch nach dem Verschieben dieselben Daten sehen.

Neu bauen:

```bash
./Scripts/build_app.sh
```

Alle Prüfungen:

```bash
./Scripts/run_checks.sh
```

## Codex-Zugriff

Die Projektkonfiguration unter `.codex/config.toml` registriert den lokalen MCP-Server `freundeblick`. Er bietet Lesewerkzeuge:

- `search_people`
- `get_person`
- `get_relationships`
- `get_groups`
- `get_media_previews`
- `query_friend_library`

Zusätzlich stehen atomar speichernde Schreibwerkzeuge bereit:

- `save_person`
- `save_profile_link`
- `save_relationship`
- `save_observation`

Es gibt bewusst keine MCP-Löschwerkzeuge und keinen Zugriff auf Originalmedien. Neue
Beobachtungen werden standardmäßig als unbestätigt gespeichert. Wenn du von Codex
zur App zurückkehrst, lädt die App externe Änderungen neu.

Nach einem Neustart von Codex ist der Server in diesem Projekt verfügbar. Der Status lässt sich prüfen mit:

```bash
codex mcp list
```

Eine direkte Kontrolle ohne MCP:

```bash
python3 Tools/freundeblick_cli.py --data FreundeblickData/friends.json ask "Wer ist Leni?"
```

## Technischer Stand

Das MVP verwendet ein atomar geschriebenes, evidenzbasiertes JSON-Modell. Für sehr große Bibliotheken oder parallele Schreibzugriffe ist als nächster technischer Schritt eine Migration auf SQLite mit WAL sinnvoll. Die MCP-Werkzeuge bleiben dabei unverändert, sodass sich die Oberfläche und die Codex-Abfragen nicht ändern müssen.

Voraussetzung: macOS 14 oder neuer.
