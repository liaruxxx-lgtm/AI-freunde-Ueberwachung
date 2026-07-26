import AppKit
import CoreLocation
@preconcurrency import MapKit
import SwiftUI

struct ProfileDetailCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

struct ProfileDetailDefinition: Identifiable, Hashable {
    let id: String
    let label: String
    let categoryID: String
    let systemImage: String
    let suggestions: [String]
}

struct ProfileColorChoice: Identifiable, Hashable {
    let name: String
    let hex: String

    var id: String { name }
}

enum ProfileColorCodec {
    static let choices: [ProfileColorChoice] = [
        ProfileColorChoice(name: "Blau", hex: "#3478F6"),
        ProfileColorChoice(name: "Grün", hex: "#34C759"),
        ProfileColorChoice(name: "Rot", hex: "#FF3B30"),
        ProfileColorChoice(name: "Lila", hex: "#AF52DE"),
        ProfileColorChoice(name: "Rosa", hex: "#FF2D55"),
        ProfileColorChoice(name: "Gelb", hex: "#FFCC00"),
        ProfileColorChoice(name: "Orange", hex: "#FF9500"),
        ProfileColorChoice(name: "Türkis", hex: "#30B0C7"),
        ProfileColorChoice(name: "Beige", hex: "#D8C3A5"),
        ProfileColorChoice(name: "Braun", hex: "#8B5E3C"),
        ProfileColorChoice(name: "Gold", hex: "#D4AF37"),
        ProfileColorChoice(name: "Silber", hex: "#B8BCC2"),
        ProfileColorChoice(name: "Grau", hex: "#8E8E93"),
        ProfileColorChoice(name: "Schwarz", hex: "#1C1C1E"),
        ProfileColorChoice(name: "Weiß", hex: "#FFFFFF"),
    ]

    static func color(for value: String) -> Color? {
        if let choice = choices.first(where: {
            $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame
        }) {
            return color(fromHex: choice.hex)
        }
        guard let hex = normalizedHex(value) else { return nil }
        return color(fromHex: hex)
    }

    static func displayName(for value: String) -> String {
        normalizedHex(value) == nil ? value : "Eigene Farbe"
    }

    static func storageValue(for color: Color) -> String? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }
        let red = colorByte(converted.redComponent)
        let green = colorByte(converted.greenComponent)
        let blue = colorByte(converted.blueComponent)
        let hex = String(
            format: "#%02X%02X%02X",
            min(max(red, 0), 255),
            min(max(green, 0), 255),
            min(max(blue, 0), 255)
        )
        return choices.first(where: { $0.hex == hex })?.name ?? hex
    }

    static func normalizedHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7, trimmed.first == "#" else { return nil }
        let digits = String(trimmed.dropFirst())
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(digits.uppercased())"
    }

    private static func color(fromHex hex: String) -> Color? {
        guard let normalized = normalizedHex(hex),
              let rgb = UInt64(normalized.dropFirst(), radix: 16)
        else {
            return nil
        }
        return Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }

    private static func colorByte(_ component: CGFloat) -> Int {
        Int(floor(component * 255 + 0.500_001))
    }
}

enum ProfileSuggestionCatalog {
    static let genderIdentities = [
        "Frau",
        "Mann",
        "nichtbinär",
        "genderfluid",
        "agender",
        "divers",
        "trans Frau",
        "trans Mann",
        "intergeschlechtlich",
        "queer",
    ]

    static let sexualOrientations = [
        "heterosexuell",
        "homosexuell",
        "lesbisch",
        "schwul",
        "bisexuell",
        "pansexuell",
        "asexuell",
        "demisexuell",
        "queer",
        "noch offen",
    ]

    static let detailCategories = [
        ProfileDetailCategory(id: "favorites", title: "Lieblingssachen", systemImage: "heart.fill"),
        ProfileDetailCategory(id: "food", title: "Essen & Trinken", systemImage: "fork.knife"),
        ProfileDetailCategory(id: "media", title: "Musik, Medien & Freizeit", systemImage: "play.rectangle.fill"),
        ProfileDetailCategory(id: "style", title: "Stil, Marken & Dinge", systemImage: "tshirt.fill"),
        ProfileDetailCategory(id: "everyday", title: "Alltag & Eigenheiten", systemImage: "clock.fill"),
        ProfileDetailCategory(id: "organizations", title: "Vereine & öffentliches Umfeld", systemImage: "person.3.fill"),
        ProfileDetailCategory(id: "dreams", title: "Träume & Quatschfragen", systemImage: "sparkles"),
    ]

    static let profileDetails: [ProfileDetailDefinition] = [
        detail("favoriteColors", "Lieblingsfarbe", "favorites", "paintpalette.fill",
               ["Blau", "Grün", "Rot", "Lila", "Rosa", "Schwarz", "Weiß", "Grau", "Gelb", "Orange", "Türkis", "Beige", "Braun", "Gold", "Silber"]),
        detail("favoriteAnimals", "Lieblingstier", "favorites", "pawprint.fill",
               ["Hund", "Katze", "Pferd", "Delfin", "Fuchs", "Wolf", "Panda", "Otter", "Löwe", "Tiger", "Elefant", "Eule", "Pinguin", "Hase"]),
        detail("favoriteFlowers", "Lieblingsblume", "favorites", "camera.macro",
               ["Rose", "Sonnenblume", "Tulpe", "Lavendel", "Orchidee", "Pfingstrose", "Gänseblümchen", "Lilie", "Mohn"]),
        detail("favoritePlaces", "Lieblingsort", "favorites", "mappin.and.ellipse",
               ["Zuhause", "Meer", "Strand", "Berge", "Wald", "See", "Großstadt", "Café", "Kino", "Park"]),
        detail("favoriteSeasons", "Lieblingsjahreszeit", "favorites", "leaf.fill",
               ["Frühling", "Sommer", "Herbst", "Winter"]),
        detail("favoriteWeather", "Lieblingswetter", "favorites", "cloud.sun.fill",
               ["Sonnig", "Warm", "Regen", "Gewitter", "Schnee", "Kühl", "Windig", "Nebel"]),

        detail("favoriteFoods", "Lieblingsessen", "food", "fork.knife",
               ["Pizza", "Pasta", "Burger", "Sushi", "Döner", "Curry", "Lasagne", "Tacos", "Salat", "Kartoffeln", "Ramen", "Schnitzel", "Pfannkuchen"]),
        detail("favoriteDrinks", "Lieblingsgetränk", "food", "cup.and.saucer.fill",
               ["Wasser", "Kaffee", "Tee", "Cola", "Limonade", "Saft", "Kakao", "Eistee", "Energy", "Milchshake"]),
        detail("favoriteSnacks", "Lieblingssnack", "food", "takeoutbag.and.cup.and.straw.fill",
               ["Chips", "Popcorn", "Nüsse", "Obst", "Cracker", "Nachos", "Salzstangen", "Gemüsesticks"]),
        detail("favoriteSweets", "Lieblingssüßigkeit", "food", "birthday.cake.fill",
               ["Schokolade", "Gummibärchen", "Kekse", "Kuchen", "Bonbons", "Lakritz", "Donuts", "Brownies"]),
        detail("favoriteIceCream", "Lieblingseis", "food", "snowflake",
               ["Vanille", "Schokolade", "Erdbeere", "Stracciatella", "Pistazie", "Mango", "Zitrone", "Cookie", "Joghurt"]),
        detail("favoriteRestaurants", "Lieblingsrestaurant", "food", "storefront.fill", []),
        detail("dislikedFoods", "Mag dieses Essen gar nicht", "food", "hand.thumbsdown.fill",
               ["Pilze", "Oliven", "Fisch", "Spinat", "Rosenkohl", "Zwiebeln", "Käse", "Scharfes Essen", "Koriander"]),
        detail("pizzaToppings", "Pizza-Belag", "food", "circle.grid.cross.fill",
               ["Salami", "Margherita", "Schinken", "Pilze", "Thunfisch", "Ananas", "Oliven", "Peperoni", "Vier Käse"]),
        detail("breakfast", "Typisches Frühstück", "food", "sunrise.fill",
               ["Müsli", "Brötchen", "Toast", "Porridge", "Obst", "Joghurt", "Ei", "Kein Frühstück"]),

        detail("musicGenres", "Musikrichtung", "media", "music.note.list",
               ["Pop", "Rock", "Hip-Hop", "Rap", "Techno", "House", "Indie", "Metal", "Schlager", "Klassik", "Jazz", "R&B", "Drum and Bass"]),
        detail("favoriteArtists", "Lieblingsartist oder Band", "media", "music.mic", []),
        detail("favoriteSongs", "Lieblingssong", "media", "music.note", []),
        detail("favoriteFilms", "Lieblingsfilm", "media", "film.fill", []),
        detail("favoriteSeries", "Lieblingsserie", "media", "tv.fill", []),
        detail("favoriteBooks", "Lieblingsbuch", "media", "books.vertical.fill", []),
        detail("favoriteGames", "Lieblingsspiel", "media", "gamecontroller.fill",
               ["Minecraft", "Fortnite", "Mario Kart", "FIFA", "Die Sims", "GTA", "Valorant", "Pokémon", "Animal Crossing", "Brettspiele"]),
        detail("favoriteSports", "Lieblingssport", "media", "figure.run",
               ["Fußball", "Fitness", "Tanzen", "Schwimmen", "Reiten", "Tennis", "Badminton", "Basketball", "Volleyball", "Fahrradfahren", "Wandern"]),
        detail("favoriteClubs", "Lieblingsverein", "media", "sportscourt.fill", []),
        detail("favoritePodcasts", "Lieblingspodcast", "media", "waveform", []),

        detail("carBrands", "Lieblingsautomarke", "style", "car.fill",
               ["Audi", "BMW", "Mercedes-Benz", "Volkswagen", "Porsche", "Tesla", "Toyota", "Ford", "Volvo", "Ferrari", "Lamborghini", "Škoda", "Opel"]),
        detail("clothingBrands", "Lieblings-Kleidungsmarke", "style", "tshirt.fill",
               ["Nike", "Adidas", "Puma", "Zara", "H&M", "Levi’s", "The North Face", "Carhartt", "New Balance", "Patagonia"]),
        detail("shoeBrands", "Lieblings-Schuhmarke", "style", "shoe.2.fill",
               ["Nike", "Adidas", "Vans", "Converse", "New Balance", "Puma", "Dr. Martens", "Birkenstock"]),
        detail("techBrands", "Lieblings-Technikmarke", "style", "laptopcomputer",
               ["Apple", "Samsung", "Sony", "Microsoft", "Google", "Nintendo", "Logitech", "Bose"]),
        detail("fragrances", "Lieblingsduft", "style", "aqi.medium",
               ["Frisch", "Blumig", "Süß", "Holzig", "Zitrisch", "Vanille", "Kokos", "Lavendel"]),
        detail("favoriteAccessories", "Lieblingsaccessoire", "style", "sunglasses",
               ["Uhr", "Kette", "Ring", "Armband", "Mütze", "Cap", "Sonnenbrille", "Tasche"]),

        detail("morningEvening", "Morgen- oder Abendmensch", "everyday", "sun.horizon.fill",
               ["Morgenmensch", "Abendmensch", "Nachteule", "Kommt auf den Tag an"]),
        detail("coffeeTea", "Kaffee oder Tee", "everyday", "cup.and.saucer.fill",
               ["Kaffee", "Tee", "Beides", "Keins"]),
        detail("sweetSalty", "Süß oder salzig", "everyday", "plusminus",
               ["Süß", "Salzig", "Beides"]),
        detail("summerWinter", "Sommer oder Winter", "everyday", "sun.snow.fill",
               ["Sommer", "Winter", "Frühling", "Herbst"]),
        detail("cityCountry", "Stadt oder Land", "everyday", "building.2.fill",
               ["Großstadt", "Kleinstadt", "Dorf", "Land", "Irgendwo dazwischen"]),
        detail("planningStyle", "Planer oder spontan", "everyday", "calendar.badge.clock",
               ["Plant alles", "Eher geplant", "Spontan", "Komplett chaotisch"]),
        detail("punctuality", "Pünktlichkeit", "everyday", "clock.badge.checkmark.fill",
               ["Immer zu früh", "Pünktlich", "Meist knapp", "Chronisch zu spät"]),
        detail("petPeeves", "Kleine Nervigkeiten", "everyday", "exclamationmark.bubble.fill",
               ["Lautes Kauen", "Unpünktlichkeit", "Unordnung", "Langsame Menschen", "Spoiler", "Smalltalk", "Leere Akkus"]),
        detail("talents", "Talente", "everyday", "star.circle.fill", []),
        detail("languages", "Sprachen", "everyday", "character.bubble.fill",
               ["Deutsch", "Englisch", "Spanisch", "Französisch", "Italienisch", "Türkisch", "Polnisch", "Arabisch", "Russisch"]),
        detail("collections", "Sammelt gern", "everyday", "square.stack.3d.up.fill",
               ["Sneaker", "Schallplatten", "Bücher", "Münzen", "Karten", "Pflanzen", "Magnete", "Fotos", "Nichts"]),

        detail("organizations", "Verein oder Organisation", "organizations", "person.3.fill", []),
        detail("trainingPlaces", "Trainingsort", "organizations", "mappin.and.ellipse", []),
        detail("confirmedPublicFacts", "Bestätigte öffentliche Info", "organizations", "checkmark.seal.fill", []),

        detail("dreamDestinations", "Traumreiseziel", "dreams", "airplane",
               ["Japan", "Island", "New York", "Australien", "Malediven", "Norwegen", "Kanada", "Italien", "Neuseeland", "Weltreise"]),
        detail("dreamJob", "Traumberuf", "dreams", "briefcase.fill", []),
        detail("superpower", "Gewünschte Superkraft", "dreams", "bolt.fill",
               ["Fliegen", "Unsichtbar sein", "Teleportation", "Gedanken lesen", "Zeit anhalten", "Heilen", "Unter Wasser atmen"]),
        detail("lotteryPlan", "Was bei einem Lottogewinn?", "dreams", "eurosign.circle.fill",
               ["Reisen", "Haus kaufen", "Familie unterstützen", "Spenden", "Auto kaufen", "Nicht mehr arbeiten", "Investieren"]),
        detail("favoriteEmojis", "Lieblingsemoji", "dreams", "face.smiling.inverse",
               ["😂", "❤️", "😭", "😍", "🥰", "✨", "🔥", "👍", "🤝", "🫶", "🙃", "💀"]),
        detail("karaokeSongs", "Karaoke-Song", "dreams", "music.mic.circle.fill", []),
        detail("uselessTalents", "Unnützes Talent", "dreams", "wand.and.stars", []),
        detail("weirdHabits", "Seltsame Gewohnheit", "dreams", "questionmark.bubble.fill", []),
        detail("pineapplePizza", "Ananas auf Pizza?", "dreams", "hand.thumbsup.fill",
               ["Ja", "Nein", "Nur manchmal", "Ist mir egal"]),
        detail("sockStyle", "Sockenstil", "dreams", "circle.hexagongrid.fill",
               ["Schwarz", "Weiß", "Bunt", "Mit Motiven", "Immer unterschiedlich", "Hauptsache bequem"]),
    ]

    static let temperament = [
        "ruhig",
        "aufmerksam",
        "offen",
        "freundlich",
        "humorvoll",
        "zuverlässig",
        "kreativ",
        "neugierig",
        "spontan",
        "geduldig",
        "hilfsbereit",
        "ehrlich",
        "einfühlsam",
        "gesellig",
        "zurückhaltend",
        "optimistisch",
        "nachdenklich",
        "abenteuerlustig",
        "entspannt",
        "zielstrebig",
        "direkt",
        "warmherzig",
        "organisiert",
        "loyal",
    ]

    static let interests = [
        "Musik",
        "Kochen",
        "Backen",
        "Lesen",
        "Filme",
        "Serien",
        "Fotografie",
        "Reisen",
        "Wandern",
        "Fahrradfahren",
        "Fitness",
        "Fußball",
        "Tanzen",
        "Gaming",
        "Brettspiele",
        "Kunst",
        "Zeichnen",
        "Handarbeit",
        "Garten",
        "Natur",
        "Tiere",
        "Technik",
        "Programmieren",
        "Konzerte",
        "Theater",
        "Sprachen",
        "Geschichte",
        "Podcasts",
        "Meditation",
        "Schwimmen",
        "Badminton",
    ]

    static let mediaTags = [
        "Urlaub",
        "Geburtstag",
        "Ausflug",
        "Feier",
        "Familie",
        "Freunde",
        "Schule",
        "Arbeit",
        "Konzert",
        "Festival",
        "Restaurant",
        "Café",
        "Natur",
        "Strand",
        "Berge",
        "Stadt",
        "Sport",
        "Selfie",
        "Gruppenfoto",
        "Erinnerung",
    ]

    static func matches(
        _ query: String,
        in suggestions: [String],
        excluding selected: [String] = []
    ) -> [String] {
        let needle = normalized(query)
        let selectedValues = Set(selected.map(normalized))
        let unique = Dictionary(
            suggestions.map { (normalized($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return unique
            .filter { key, _ in
                !selectedValues.contains(key)
                    && (needle.isEmpty || key.contains(needle))
            }
            .sorted { first, second in
                let firstStarts = first.key.hasPrefix(needle)
                let secondStarts = second.key.hasPrefix(needle)
                if firstStarts != secondStarts {
                    return firstStarts
                }
                return first.value.localizedCaseInsensitiveCompare(second.value)
                    == .orderedAscending
            }
            .map(\.value)
    }

    static func definition(for key: String) -> ProfileDetailDefinition? {
        profileDetails.first { $0.id == key }
    }

    static func displayLabel(for key: String) -> String {
        if key == "genderIdentity" {
            return "Geschlecht / Geschlechtsidentität"
        }
        if key == "sexualOrientation" {
            return "Sexuelle Orientierung"
        }
        if let definition = definition(for: key) {
            return definition.label
        }
        if key.hasPrefix("custom:") {
            return String(key.dropFirst("custom:".count))
        }
        return key
    }

    private static func detail(
        _ id: String,
        _ label: String,
        _ categoryID: String,
        _ systemImage: String,
        _ suggestions: [String]
    ) -> ProfileDetailDefinition {
        ProfileDetailDefinition(
            id: id,
            label: label,
            categoryID: categoryID,
            systemImage: systemImage,
            suggestions: suggestions
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

struct ProfileDetailsEditor: View {
    @Binding var details: [String: [String]]

    @State private var expandedCategoryID: String? = "favorites"
    @State private var customLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Eine Kategorie gleichzeitig",
                    systemImage: "rectangle.compress.vertical"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.berry)
                Spacer()
                if expandedCategoryID != nil {
                    Button("Zuklappen") {
                        withAnimation {
                            expandedCategoryID = nil
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 2)

            ForEach(ProfileSuggestionCatalog.detailCategories) { category in
                DisclosureGroup(
                    isExpanded: expansionBinding(for: category.id)
                ) {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 245, maximum: 360),
                                spacing: 12,
                                alignment: .top
                            )
                        ],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(definitions(in: category.id)) { definition in
                            detailField(definition)
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    HStack {
                        Label(category.title, systemImage: category.systemImage)
                            .font(.callout.weight(.semibold))
                        Spacer()
                        let count = savedCount(in: category.id)
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.berry)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AppTheme.berry.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .padding(12)
                .background(
                    expandedCategoryID == category.id
                        ? AppTheme.berry.opacity(0.07)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }

            DisclosureGroup(isExpanded: expansionBinding(for: "custom")) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(customKeys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label(
                                    ProfileSuggestionCatalog.displayLabel(for: key),
                                    systemImage: "square.and.pencil"
                                )
                                .font(.caption.weight(.semibold))
                                Spacer()
                                Button(role: .destructive) {
                                    details.removeValue(forKey: key)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Eigene Rubrik entfernen")
                            }
                            TokenSuggestionField(
                                title: ProfileSuggestionCatalog.displayLabel(for: key),
                                placeholder: "Wert eingeben",
                                suggestions: [],
                                tint: AppTheme.plum,
                                values: valuesBinding(for: key)
                            )
                        }
                    }

                    HStack {
                        TextField("Eigene Rubrik, z. B. Lieblingswort", text: $customLabel)
                        Button("Hinzufügen", action: addCustomDetail)
                            .disabled(
                                customLabel.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                            )
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Eigene Angaben", systemImage: "plus.square.on.square")
                    .font(.callout.weight(.semibold))
            }
            .padding(12)
            .background(
                expandedCategoryID == "custom"
                    ? AppTheme.berry.opacity(0.07)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 14)
            )

            Text("Beim Öffnen einer Kategorie wird die vorherige automatisch geschlossen. Alle Angaben sind freiwillig; eigene Begriffe und eigene Rubriken sind immer möglich.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detailField(_ definition: ProfileDetailDefinition) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(definition.label, systemImage: definition.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.plum)
            if definition.id == "favoriteColors" {
                FavoriteColorPickerField(
                    values: valuesBinding(for: definition.id)
                )
            } else {
                TokenSuggestionField(
                    title: definition.label,
                    placeholder: "\(definition.label) eingeben",
                    suggestions: definition.suggestions,
                    tint: AppTheme.berry,
                    values: valuesBinding(for: definition.id)
                )
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color.white.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 13)
        )
    }

    private func definitions(in categoryID: String) -> [ProfileDetailDefinition] {
        ProfileSuggestionCatalog.profileDetails.filter {
            $0.categoryID == categoryID
        }
    }

    private func savedCount(in categoryID: String) -> Int {
        definitions(in: categoryID).filter {
            !(details[$0.id] ?? []).isEmpty
        }.count
    }

    private var customKeys: [String] {
        details.keys
            .filter { $0.hasPrefix("custom:") }
            .sorted {
                ProfileSuggestionCatalog.displayLabel(for: $0)
                    .localizedCaseInsensitiveCompare(
                        ProfileSuggestionCatalog.displayLabel(for: $1)
                    ) == .orderedAscending
            }
    }

    private func expansionBinding(for categoryID: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategoryID == categoryID },
            set: { expanded in
                withAnimation {
                    if expanded {
                        expandedCategoryID = categoryID
                    } else if expandedCategoryID == categoryID {
                        expandedCategoryID = nil
                    }
                }
            }
        )
    }

    private func valuesBinding(for key: String) -> Binding<[String]> {
        Binding(
            get: { details[key] ?? [] },
            set: { values in
                if values.isEmpty {
                    details.removeValue(forKey: key)
                } else {
                    details[key] = values
                }
            }
        )
    }

    private func addCustomDetail() {
        let label = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        let existingKey = customKeys.first {
            ProfileSuggestionCatalog.displayLabel(for: $0)
                .localizedCaseInsensitiveCompare(label) == .orderedSame
        }
        if existingKey == nil {
            details["custom:\(label)"] = []
        }
        customLabel = ""
    }
}

struct FavoriteColorPickerField: View {
    @Binding var values: [String]

    @State private var selectedColor = Color(
        .sRGB,
        red: 52.0 / 255,
        green: 120.0 / 255,
        blue: 246.0 / 255,
        opacity: 1
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ColorPicker(
                "Farbspektrum",
                selection: $selectedColor,
                supportsOpacity: false
            )
            .font(.callout.weight(.semibold))

            Button(action: addSelectedColor) {
                Label(
                    "Ausgewählte Farbe hinzufügen",
                    systemImage: "plus.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(AppTheme.berry)

            Text("Oder eine häufige Farbe direkt auswählen")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 7) {
                ForEach(ProfileColorCodec.choices) { choice in
                    Button {
                        add(choice.name)
                    } label: {
                        HStack(spacing: 6) {
                            colorCircle(
                                ProfileColorCodec.color(for: choice.name)
                                    ?? .clear
                            )
                            Text(choice.name)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Color.white.opacity(0.72),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(Color.black.opacity(0.09))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(contains(choice.name))
                    .opacity(contains(choice.name) ? 0.45 : 1)
                }
            }

            if !values.isEmpty {
                Divider()
                Text("Ausgewählte Lieblingsfarben")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 7) {
                    ForEach(values, id: \.self) { value in
                        Button {
                            remove(value)
                        } label: {
                            HStack(spacing: 6) {
                                colorCircle(
                                    ProfileColorCodec.color(for: value)
                                        ?? AppTheme.berry
                                )
                                Text(ProfileColorCodec.displayName(for: value))
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                (ProfileColorCodec.color(for: value)
                                    ?? AppTheme.berry).opacity(0.16),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        (ProfileColorCodec.color(for: value)
                                            ?? AppTheme.berry).opacity(0.42)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .help("\(ProfileColorCodec.displayName(for: value)) entfernen")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lieblingsfarben aus dem Farbspektrum auswählen")
    }

    private func colorCircle(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 15, height: 15)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            }
    }

    private func addSelectedColor() {
        guard let value = ProfileColorCodec.storageValue(for: selectedColor) else {
            return
        }
        add(value)
    }

    private func add(_ value: String) {
        guard !contains(value) else { return }
        values.append(value)
    }

    private func contains(_ value: String) -> Bool {
        values.contains {
            $0.localizedCaseInsensitiveCompare(value) == .orderedSame
        }
    }

    private func remove(_ value: String) {
        values.removeAll {
            $0.localizedCaseInsensitiveCompare(value) == .orderedSame
        }
    }
}

struct ProfileColorValuesView: View {
    let values: [String]

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(values, id: \.self) { value in
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            ProfileColorCodec.color(for: value)
                                ?? AppTheme.berry
                        )
                        .frame(width: 15, height: 15)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                        }
                    Text(ProfileColorCodec.displayName(for: value))
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    (ProfileColorCodec.color(for: value)
                        ?? AppTheme.berry).opacity(0.15),
                    in: Capsule()
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Lieblingsfarben: "
                + values.map { ProfileColorCodec.displayName(for: $0) }
                    .joined(separator: ", ")
        )
    }
}

struct TokenSuggestionField: View {
    let title: String
    let placeholder: String
    let suggestions: [String]
    let tint: Color
    @Binding var values: [String]

    @State private var input = ""
    @State private var suggestionsExpanded = false

    private var matches: [String] {
        ProfileSuggestionCatalog.matches(
            input,
            in: suggestions,
            excluding: values
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $input)
                    .onSubmit(addBestMatch)

                Button(action: addBestMatch) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(tint)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Eingabe hinzufügen")

                Button {
                    suggestionsExpanded.toggle()
                } label: {
                    Label(
                        "Vorschläge",
                        systemImage: suggestionsExpanded
                            ? "chevron.up.circle.fill"
                            : "chevron.down.circle"
                    )
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(suggestionsExpanded ? "Vorschläge einklappen" : "Vorschläge ausklappen")
            }

            if !values.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(values, id: \.self) { value in
                        Button {
                            values.removeAll {
                                $0.localizedCaseInsensitiveCompare(value) == .orderedSame
                            }
                        } label: {
                            Label(value, systemImage: "xmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(tint.opacity(0.11), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("\(value) entfernen")
                    }
                }
            }

            if shouldShowSuggestions {
                VStack(alignment: .leading, spacing: 7) {
                    Text(
                        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Häufige Vorschläge"
                            : "Passende Vorschläge"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if matches.isEmpty {
                        Text("Keine fertige Auswahl – mit Return kannst du deinen eigenen Eintrag übernehmen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 7) {
                            ForEach(matches.prefix(18), id: \.self) { suggestion in
                                Button(suggestion) {
                                    add(suggestion)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(tint)
                            }
                        }
                    }
                }
                .padding(10)
                .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var shouldShowSuggestions: Bool {
        suggestionsExpanded
            || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addBestMatch() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let best = matches.first,
           best.localizedCaseInsensitiveContains(trimmed) {
            add(best)
        } else {
            add(trimmed)
        }
    }

    private func add(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !values.contains(where: {
            $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            values.append(trimmed)
        }
        input = ""
    }
}

final class LocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
            span: MKCoordinateSpan(latitudeDelta: 9.5, longitudeDelta: 12.5)
        )
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            completions = []
            errorMessage = nil
            completer.queryFragment = ""
            return
        }
        errorMessage = nil
        completer.queryFragment = trimmed
    }

    func clear() {
        completions = []
        errorMessage = nil
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(8))
        DispatchQueue.main.async {
            self.completions = results
            self.errorMessage = nil
        }
    }

    func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        DispatchQueue.main.async {
            self.completions = []
            self.errorMessage = "Ortsvorschläge sind gerade nicht erreichbar."
        }
    }
}

struct LocationAutocompleteField: View {
    @Binding var location: String

    @StateObject private var search = LocationSearchService()
    @State private var showingMap = false
    @State private var selectingSuggestion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Wohnort", text: $location)
                    .onChange(of: location) { _, newValue in
                        if selectingSuggestion {
                            selectingSuggestion = false
                        } else {
                            search.update(query: newValue)
                        }
                    }

                if !location.isEmpty {
                    Button {
                        location = ""
                        search.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Wohnort leeren")
                }

                Button {
                    showingMap = true
                } label: {
                    Label("Auf Karte wählen", systemImage: "map.fill")
                }
                .buttonStyle(.bordered)
            }

            if !search.completions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(
                        Array(search.completions.prefix(6).enumerated()),
                        id: \.offset
                    ) { index, completion in
                        Button {
                            select(completion)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(AppTheme.berry)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(completion.title)
                                        .font(.callout.weight(.semibold))
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)

                        if index < min(search.completions.count, 6) - 1 {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.berry.opacity(0.2))
                }
            }

            if let errorMessage = search.errorMessage {
                Label(errorMessage, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Vorschläge und Karte werden von Apple Karten bereitgestellt. Dabei wird dein eingegebener Ortssuchtext an Apple gesendet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingMap) {
            LocationMapPickerView(initialLocation: location) { selectedLocation in
                selectingSuggestion = true
                location = selectedLocation
                search.clear()
            }
        }
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        selectingSuggestion = true
        location = completion.title
        search.clear()
    }
}

private struct LocationMapPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (String) -> Void

    @StateObject private var search = LocationSearchService()
    @State private var query: String
    @State private var selectedName: String
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var isResolving = false
    @State private var errorMessage: String?

    init(initialLocation: String, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        _query = State(initialValue: initialLocation)
        _selectedName = State(initialValue: initialLocation)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wohnort auf der Karte wählen")
                        .font(.title2.weight(.bold))
                    Text("Suche einen Ort oder klicke direkt in die Karte.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Übernehmen") {
                    onSelect(selectedName)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.berry)
                .disabled(
                    selectedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isResolving
                )
            }
            .padding(18)

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Ort suchen", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: query) { _, value in
                            search.update(query: value)
                        }

                    if isResolving {
                        ProgressView("Ort wird geladen …")
                            .controlSize(.small)
                    }

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(
                                Array(search.completions.enumerated()),
                                id: \.offset
                            ) { _, completion in
                                Button {
                                    resolve(completion)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(completion.title)
                                            .font(.callout.weight(.semibold))
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    AppTheme.berry.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                            }
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.coral)
                    }

                    Spacer()

                    if !selectedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(selectedName, systemImage: "mappin.and.ellipse")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.plum)
                    }
                }
                .padding(14)
                .frame(minWidth: 245, idealWidth: 280, maxWidth: 330)

                SelectableMapView(
                    selectedCoordinate: $selectedCoordinate,
                    onCoordinateSelected: reverseGeocode
                )
                .frame(minWidth: 480, minHeight: 480)
            }
        }
        .frame(minWidth: 800, idealWidth: 920, minHeight: 560, idealHeight: 640)
        .onAppear {
            search.update(query: query)
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        errorMessage = nil
        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { response, error in
            DispatchQueue.main.async {
                isResolving = false
                guard let item = response?.mapItems.first else {
                    errorMessage = error?.localizedDescription
                        ?? "Dieser Ort konnte nicht auf der Karte geöffnet werden."
                    return
                }
                selectedCoordinate = item.placemark.coordinate
                selectedName = completion.title
                query = completion.title
                search.clear()
            }
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        isResolving = true
        errorMessage = nil
        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        ) { placemarks, error in
            DispatchQueue.main.async {
                isResolving = false
                guard let placemark = placemarks?.first else {
                    errorMessage = error?.localizedDescription
                        ?? "Für diese Kartenposition wurde kein Ort gefunden."
                    return
                }
                let place = placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea
                    ?? placemark.name
                guard let place, !place.isEmpty else {
                    errorMessage = "Für diese Kartenposition wurde kein Ortsname gefunden."
                    return
                }
                selectedName = place
                query = place
                search.clear()
            }
        }
    }
}

private struct SelectableMapView: NSViewRepresentable {
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    let onCoordinateSelected: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ClickableMapView {
        let mapView = ClickableMapView()
        mapView.showsZoomControls = true
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
                span: MKCoordinateSpan(latitudeDelta: 9.5, longitudeDelta: 12.5)
            ),
            animated: false
        )
        mapView.onCoordinateSelected = { coordinate in
            context.coordinator.select(coordinate)
        }
        return mapView
    }

    func updateNSView(_ mapView: ClickableMapView, context: Context) {
        context.coordinator.parent = self
        mapView.removeAnnotations(mapView.annotations)
        guard let selectedCoordinate else { return }

        let annotation = MKPointAnnotation()
        annotation.coordinate = selectedCoordinate
        annotation.title = "Ausgewählter Wohnort"
        mapView.addAnnotation(annotation)

        if context.coordinator.shouldCenter(on: selectedCoordinate) {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: selectedCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
                ),
                animated: true
            )
        }
    }

    final class Coordinator {
        var parent: SelectableMapView
        private var lastCenteredCoordinate: CLLocationCoordinate2D?

        init(parent: SelectableMapView) {
            self.parent = parent
        }

        func select(_ coordinate: CLLocationCoordinate2D) {
            parent.selectedCoordinate = coordinate
            parent.onCoordinateSelected(coordinate)
        }

        func shouldCenter(on coordinate: CLLocationCoordinate2D) -> Bool {
            defer { lastCenteredCoordinate = coordinate }
            guard let previous = lastCenteredCoordinate else { return true }
            return abs(previous.latitude - coordinate.latitude) > 0.000_01
                || abs(previous.longitude - coordinate.longitude) > 0.000_01
        }
    }
}

private final class ClickableMapView: MKMapView {
    var onCoordinateSelected: ((CLLocationCoordinate2D) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let coordinate = convert(point, toCoordinateFrom: self)
        onCoordinateSelected?(coordinate)
        super.mouseDown(with: event)
    }
}
