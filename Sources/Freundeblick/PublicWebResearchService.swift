import Foundation

struct PublicKnowledgeResult: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let url: URL
    let excerpt: String

    var hostLabel: String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? "Wikipedia"
    }
}

struct ContextResearchQuery: Identifiable, Hashable, Sendable {
    let clue: String
    let text: String

    var id: String { "\(clue.lowercased())|\(text.lowercased())" }
}

struct PublicWebResult: Identifiable, Hashable, Sendable {
    let title: String
    let url: URL
    let excerpt: String
    let matchedClues: [String]

    var id: String { url.absoluteString }
    var hostLabel: String { PublicWebResearchService.displayHost(for: url) }
}

enum ContextResearchPlanner {
    static func queries(
        location: String?,
        clues: [String]
    ) -> [ContextResearchQuery] {
        let cleanLocation = location?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanClues = uniqueCleanValues(clues).prefix(3)

        return cleanClues.flatMap { clue in
            let localContext = [clue, cleanLocation]
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            return [
                ContextResearchQuery(
                    clue: clue,
                    text: "\(localContext) Verein Club Training"
                ),
                ContextResearchQuery(
                    clue: clue,
                    text: "\(localContext) Instagram Facebook"
                )
            ]
        }
    }

    static func uniqueCleanValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            let key = clean.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "de_DE")
            )
            guard seen.insert(key).inserted else { return nil }
            return clean
        }
    }
}

enum PublicWebResearchError: LocalizedError {
    case invalidRequest
    case unexpectedResponse
    case serviceFailure(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Die Suchanfrage konnte nicht erstellt werden."
        case .unexpectedResponse:
            "Der Wissensdienst hat keine lesbare Antwort geliefert."
        case let .serviceFailure(statusCode):
            "Der Suchdienst ist gerade nicht erreichbar (HTTP \(statusCode))."
        }
    }
}

struct PublicWebResearchService: Sendable {
    private static let wikipediaEndpoint = URL(
        string: "https://de.wikipedia.org/w/api.php"
    )!

    func searchWikipedia(query: String) async throws -> [PublicKnowledgeResult] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty, cleanQuery.count <= 240 else {
            throw PublicWebResearchError.invalidRequest
        }

        var components = URLComponents(
            url: Self.wikipediaEndpoint,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: cleanQuery),
            URLQueryItem(name: "gsrnamespace", value: "0"),
            URLQueryItem(name: "gsrlimit", value: "5"),
            URLQueryItem(name: "prop", value: "info|extracts"),
            URLQueryItem(name: "inprop", value: "url"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exsentences", value: "3"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        guard let url = components?.url else {
            throw PublicWebResearchError.invalidRequest
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20

        let session = URLSession(
            configuration: configuration,
            delegate: WikipediaRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue(
            "Freundeblick/0.2 (private knowledge organizer)",
            forHTTPHeaderField: "User-Agent"
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PublicWebResearchError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PublicWebResearchError.serviceFailure(httpResponse.statusCode)
        }
        guard let finalURL = httpResponse.url,
              Self.isAllowedWikipediaURL(finalURL)
        else {
            throw PublicWebResearchError.unexpectedResponse
        }

        var data = Data()
        data.reserveCapacity(128_000)
        for try await byte in bytes {
            guard data.count < 2_000_000 else {
                throw PublicWebResearchError.unexpectedResponse
            }
            data.append(byte)
        }

        return try Self.parseWikipediaResponse(data)
    }

    func searchPublicWeb(
        queries: [ContextResearchQuery]
    ) async throws -> [PublicWebResult] {
        let approvedQueries = Array(queries.prefix(6)).filter {
            !$0.text.isEmpty && $0.text.count <= 240
        }
        guard !approvedQueries.isEmpty else {
            throw PublicWebResearchError.invalidRequest
        }

        var aggregated: [String: PublicWebResult] = [:]
        var lastError: Error?

        for query in approvedQueries {
            do {
                let results = try await searchDuckDuckGo(query: query.text)
                for result in results {
                    let key = Self.normalizedResultURL(result.url)
                    if let existing = aggregated[key] {
                        aggregated[key] = PublicWebResult(
                            title: existing.title,
                            url: existing.url,
                            excerpt: existing.excerpt.count >= result.excerpt.count
                                ? existing.excerpt
                                : result.excerpt,
                            matchedClues: ContextResearchPlanner.uniqueCleanValues(
                                existing.matchedClues + [query.clue]
                            )
                        )
                    } else {
                        aggregated[key] = PublicWebResult(
                            title: result.title,
                            url: result.url,
                            excerpt: result.excerpt,
                            matchedClues: [query.clue]
                        )
                    }
                }
            } catch {
                lastError = error
            }
        }

        if aggregated.isEmpty, let lastError {
            throw lastError
        }

        return aggregated.values
            .sorted {
                if $0.matchedClues.count != $1.matchedClues.count {
                    return $0.matchedClues.count > $1.matchedClues.count
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(30)
            .map { $0 }
    }

    static func parseDuckDuckGoResponse(_ data: Data) -> [PublicWebResult] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        let anchorPattern =
            #"(?is)<a[^>]*class\s*=\s*["'][^"']*result__a[^"']*["'][^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern) else {
            return []
        }
        let fullRange = NSRange(html.startIndex..., in: html)
        let matches = anchorRegex.matches(in: html, range: fullRange)

        return matches.enumerated().compactMap { index, match in
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html)
            else {
                return nil
            }

            let rawHref = decodeHTMLEntities(String(html[hrefRange]))
            guard let rawURL = URL(string: rawHref) else { return nil }
            let targetURL = duckDuckGoRedirectTarget(from: rawURL) ?? rawURL
            guard isSafePublicPageURL(targetURL) else { return nil }

            let tailStart = match.range.location + match.range.length
            let tailEnd = index + 1 < matches.count
                ? matches[index + 1].range.location
                : min((html as NSString).length, tailStart + 4_000)
            let tailRange = NSRange(
                location: tailStart,
                length: max(0, tailEnd - tailStart)
            )
            let snippet = snippetText(in: html, range: tailRange)

            return PublicWebResult(
                title: plainText(String(html[titleRange])),
                url: targetURL,
                excerpt: snippet.isEmpty
                    ? "Keine Vorschau verfügbar. Prüfe die Quelle selbst."
                    : snippet,
                matchedClues: []
            )
        }
    }

    static func parseWikipediaResponse(_ data: Data) throws -> [PublicKnowledgeResult] {
        let decoded = try JSONDecoder().decode(WikipediaResponse.self, from: data)
        return (decoded.query?.pages ?? [])
            .sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }
            .compactMap { page in
                guard let fullURL = URL(string: page.fullurl),
                      Self.isAllowedWikipediaURL(fullURL)
                else {
                    return nil
                }
                return PublicKnowledgeResult(
                    id: "wikipedia-\(page.pageid)",
                    title: page.title,
                    url: fullURL,
                    excerpt: cleanExcerpt(page.extract)
                )
            }
    }

    static func searchQuery(
        person: Person,
        includeLocation: Bool,
        additionalTerms: String
    ) -> String {
        var parts = ["\"\(person.name.trimmingCharacters(in: .whitespacesAndNewlines))\""]
        if includeLocation,
           let location = person.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            parts.append(location)
        }
        let extra = additionalTerms.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            parts.append(extra)
        }
        return parts.joined(separator: " ")
    }

    static func duckDuckGoSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "kl", value: "de-de"),
            URLQueryItem(name: "kp", value: "1")
        ]
        return components?.url
    }

    static func isDuckDuckGoURL(_ url: URL) -> Bool {
        guard let rawHost = url.host?.lowercased() else { return false }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == "duckduckgo.com"
            || host.hasSuffix(".duckduckgo.com")
            || host == "duck.com"
            || host.hasSuffix(".duck.com")
    }

    static func isSafePublicPageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let rawHost = url.host?.lowercased(),
              url.user == nil,
              url.password == nil
        else {
            return false
        }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard
              !host.isEmpty,
              !isPrivateHost(host),
              !isBlockedPeopleFinder(host)
        else {
            return false
        }
        return true
    }

    static func displayHost(for url: URL) -> String {
        (url.host ?? url.absoluteString)
            .lowercased()
            .replacingOccurrences(of: "www.", with: "")
    }

    static func duckDuckGoRedirectTarget(from url: URL) -> URL? {
        guard isDuckDuckGoURL(url),
              (url.path == "/l" || url.path.hasPrefix("/l/")),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawTarget = components.queryItems?.first(
                  where: { $0.name == "uddg" }
              )?.value
        else {
            return nil
        }
        return URL(string: rawTarget)
    }

    private func searchDuckDuckGo(query: String) async throws -> [PublicWebResult] {
        guard let url = Self.duckDuckGoSearchURL(query: query) else {
            throw PublicWebResearchError.invalidRequest
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 22
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue(
            "Freundeblick/0.3 (private knowledge organizer)",
            forHTTPHeaderField: "User-Agent"
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PublicWebResearchError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PublicWebResearchError.serviceFailure(httpResponse.statusCode)
        }
        guard let finalURL = httpResponse.url,
              Self.isDuckDuckGoURL(finalURL)
        else {
            throw PublicWebResearchError.unexpectedResponse
        }

        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else {
                throw PublicWebResearchError.unexpectedResponse
            }
            data.append(byte)
        }
        return Self.parseDuckDuckGoResponse(data)
    }

    private static func normalizedResultURL(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.fragment = nil
        components.host = components.host?.lowercased()
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.string ?? url.absoluteString
    }

    private static func snippetText(in html: String, range: NSRange) -> String {
        let snippetPattern =
            #"(?is)<(?:a|div)[^>]*class\s*=\s*["'][^"']*result__snippet[^"']*["'][^>]*>(.*?)</(?:a|div)>"#
        guard let regex = try? NSRegularExpression(pattern: snippetPattern),
              let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html)
        else {
            return ""
        }
        return plainText(String(html[contentRange]))
    }

    private static func plainText(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let namedEntities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&#x27;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (entity, value) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    private static func isAllowedWikipediaURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "de.wikipedia.org"
    }

    private static func cleanExcerpt(_ value: String?) -> String {
        guard let value else {
            return "Keine Kurzbeschreibung verfügbar."
        }
        let collapsed = value
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "Keine Kurzbeschreibung verfügbar." : collapsed
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host == "::1"
            || host.contains(":")
            || host.allSatisfy(\.isNumber)
            || host.allSatisfy({ $0.isNumber || $0 == "." })
            || host.hasPrefix("0x") {
            return true
        }

        let nonPublicSuffixes = [
            ".corp",
            ".home",
            ".internal",
            ".invalid",
            ".lan",
            ".localhost",
            ".local",
            ".test",
            ".nip.io",
            ".sslip.io",
            ".xip.io"
        ]
        if nonPublicSuffixes.contains(where: host.hasSuffix) {
            return true
        }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4,
              octets.allSatisfy({ (0...255).contains($0) })
        else {
            return false
        }
        return octets[0] == 10
            || octets[0] == 127
            || (octets[0] == 169 && octets[1] == 254)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || octets[0] == 0
    }

    private static func isBlockedPeopleFinder(_ host: String) -> Bool {
        let blockedDomains = [
            "11880.com",
            "anywho.com",
            "fastpeoplesearch.com",
            "peoplefinder.com",
            "peoplefinders.com",
            "peekyou.com",
            "spokeo.com",
            "thatsthem.com",
            "truepeoplesearch.com",
            "truthfinder.com",
            "whitepages.com"
        ]
        return blockedDomains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }
}

private struct WikipediaResponse: Decodable {
    let query: WikipediaQuery?
}

private struct WikipediaQuery: Decodable {
    let pages: [WikipediaPage]?
}

private struct WikipediaPage: Decodable {
    let pageid: Int
    let index: Int?
    let title: String
    let fullurl: String
    let extract: String?
}

private final class WikipediaRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "de.wikipedia.org"
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
