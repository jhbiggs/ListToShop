//
//  RecipeFetcher.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/26/26.
//

import Foundation
import SwiftSoup

#if canImport(FoundationModels)
import FoundationModels

@Generable
struct EstimatedCookTime {
    @Guide(description: "Total minutes from starting prep to having the finished dish, including prep, cooking, and resting. A whole number.")
    var minutes: Int
}
#endif

/// Estimates how long a recipe takes when the page doesn't list a time.
enum RecipeTimeEstimator {

    /// Returns total minutes from the on-device model, or nil if it's unavailable or the answer is implausible.
    static func estimateMinutes(title: String, ingredients: [String], steps: [String]) async -> Int? {
        #if canImport(FoundationModels)
        // Keep the prompt short enough for the on-device model's context window.
        let ingredientText = String(ingredients.map { "- \($0)" }.joined(separator: "\n").prefix(1500))
        let stepText = String(steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n").prefix(3000))

        let prompt = """
        Estimate how many minutes it takes to make this recipe, from starting prep to the finished dish. Include prep, cooking, and resting. Do not include shopping.
        Answer with a whole number of minutes.

        Recipe: \(title)

        Ingredients:
        \(ingredientText)

        Steps:
        \(stepText)
        """

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt, generating: EstimatedCookTime.self)
            let minutes = response.content.minutes
            return (5...480).contains(minutes) ? minutes : nil
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}


struct RecipeFetchResult {
    /// Which part of the page the recipe was read from.
    enum Source: String {
        case jsonLD = "JSON-LD"
        case html = "HTML"
    }

    let title: String
    let ingredients: [String]
    let steps: [Any]?
    /// Total time to make the recipe, from the page's totalTime (or prepTime + cookTime). Nil if the page doesn't say.
    var totalMinutes: Int? = nil
    /// JSON-LD unless the recipe came from the HTML fallback. Used by the recipe-site tests.
    var source: Source = .jsonLD
}

enum RecipeFetchError: LocalizedError {
    case invalidURL
    case noRecipeFound(host: String)
    case httpStatus(Int, host: String)
    case unreadablePage(host: String)
    case network(URLError, host: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That link isn't a valid web address."

        case .noRecipeFound(let host):
            return "No recipe found on \(host). The page has no recipe data, ingredient list, or instructions the app can read."

        case .httpStatus(let code, let host):
            switch code {
            case 401, 403:
                return "\(host) blocked the request (HTTP \(code)). Some sites block apps like this one."
            case 404, 410:
                return "That page doesn't exist on \(host) (HTTP \(code))."
            case 429:
                return "\(host) asked the app to slow down (HTTP 429). Try again in a few minutes."
            case 500...599:
                return "\(host) had a server error (HTTP \(code)). Try again later."
            default:
                return "\(host) returned HTTP \(code) instead of the page."
            }

        case .unreadablePage(let host):
            return "The page from \(host) couldn't be read as text."

        case .network(let error, let host):
            switch error.code {
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "Couldn't make a secure connection to \(host). Its security certificate may be misconfigured."
            case .timedOut:
                return "\(host) didn't respond in time."
            case .notConnectedToInternet:
                return "No internet connection."
            case .cannotFindHost, .dnsLookupFailed:
                return "Couldn't find \(host)."
            case .cannotConnectToHost:
                return "Couldn't connect to \(host)."
            default:
                return "Network error for \(host): \(error.localizedDescription)"
            }
        }
    }
}

struct RecipeFetcher {

    /// Facebook and Instagram wrap outside links in a redirect such as
    /// `https://l.facebook.com/l.php?u=<encoded destination>`. Returns the destination, or the input unchanged.
    /// Also removes Facebook's `fbclid` tracking parameter from the result.
    static func unwrapRedirect(_ urlString: String) -> String {
        var resolved = urlString
        if let url = URL(string: urlString),
           let host = url.host?.lowercased(),
           host == "l.facebook.com" || host == "lm.facebook.com",
           let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
               .queryItems?
               .first(where: { $0.name == "u" })?
               .value,
           !target.isEmpty {
            resolved = target
        }

        guard var components = URLComponents(string: resolved) else { return resolved }
        if let items = components.queryItems {
            let kept = items.filter { $0.name != "fbclid" }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.string ?? resolved
    }

    /// Downloads the HTML at `urlString`, extracts the recipe title and ingredients.
    static func fetch(from urlString: String) async throws -> RecipeFetchResult {
        guard let url = URL(string: urlString) else {
            throw RecipeFetchError.invalidURL
        }

        let host = url.host ?? urlString

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch let error as URLError {
            throw RecipeFetchError.network(error, host: host)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RecipeFetchError.httpStatus(http.statusCode, host: host)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw RecipeFetchError.unreadablePage(host: host)
        }

        let doc = try SwiftSoup.parse(html)

        // Strategy 1: JSON-LD
        if let result = try extractFromJSONLD(doc) {
            return result
        }

        // Strategy 2: Microdata / class-based fallback
        if let result = try extractFromHTML(doc) {
            return result
        }

        // Strategy 3: read the page as lines, for pages with no recipe markup
        if let result = extractFromPlainText(html) {
            return result
        }

        throw RecipeFetchError.noRecipeFound(host: host)
    }

    // MARK: - JSON-LD Extraction

    private static func extractFromJSONLD(_ doc: Document) throws -> RecipeFetchResult? {
        let scripts = try doc.select("script[type=application/ld+json]")
        for script in scripts {
            let json = script.data()
            guard let data = json.data(using: .utf8) else { continue }

            if let result = parseJSONLD(data) {
                return result
            }
        }
        return nil
    }

    private static func parseJSONLD(_ data: Data) -> RecipeFetchResult? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else { return nil }

        // Could be a single object or an array
        if let dict = jsonObject as? [String: Any] {
            return recipeFromDict(dict)
        } else if let array = jsonObject as? [[String: Any]] {
            for dict in array {
                if let result = recipeFromDict(dict) {
                    return result
                }
            }
        }
        return nil
    }

    private static func recipeFromDict(_ dict: [String: Any]) -> RecipeFetchResult? {
        // Handle @graph wrapper
        if let graph = dict["@graph"] as? [[String: Any]] {
            for node in graph {
                if let result = recipeFromDict(node) {
                    return result
                }
            }
            return nil
        }

        let isRecipe: Bool
        if let type = dict["@type"] as? String {
            isRecipe = (type == "Recipe")
        } else if let types = dict["@type"] as? [String] {
            isRecipe = types.contains("Recipe")
        } else {
            isRecipe = false
        }
        guard isRecipe else { return nil }

        let title = cleanText(dict["name"] as? String ?? "Untitled Recipe")
        guard let rawIngredients = dict["recipeIngredient"] as? [String], !rawIngredients.isEmpty else {
            return nil
        }
        
        let ingredients = rawIngredients.map(cleanText)
        let steps = dict["recipeInstructions"] as? [Any]

        let prep = minutes(fromISO8601Duration: dict["prepTime"] as? String) ?? 0
        let cook = minutes(fromISO8601Duration: dict["cookTime"] as? String) ?? 0
        let total = minutes(fromISO8601Duration: dict["totalTime"] as? String)
            ?? (prep + cook > 0 ? prep + cook : nil)

        print("Found recipe: \(title) with \(ingredients.count) ingredients and \(steps?.count ?? 0) steps")
        return RecipeFetchResult(title: title, ingredients: ingredients, steps: steps, totalMinutes: total)
    }

    // MARK: - Text Cleanup

    /// Removes leftover HTML tags, decodes common entities, and collapses extra spaces.
    static func cleanText(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"),
            ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
            ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"),
            ("&ndash;", "–"), ("&mdash;", "—"),
            ("&frac12;", "½"), ("&frac14;", "¼"), ("&frac34;", "¾"),
            ("&amp;", "&"),  // last, so "&amp;quot;" isn't decoded twice
        ]
        for (entity, replacement) in entities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Time Parsing

    /// Converts an ISO 8601 duration such as "PT1H30M" or "P0DT0H45M" into minutes.
    static func minutes(fromISO8601Duration raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        let pattern = #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)) else {
            return nil
        }

        func group(_ index: Int) -> Int {
            guard let range = Range(match.range(at: index), in: upper) else { return 0 }
            return Int(upper[range]) ?? 0
        }

        let total = group(1) * 1440 + group(2) * 60 + group(3)
        return total > 0 ? total : nil
    }

    // MARK: - Steps Extraction

    /// Converts the raw `[Any]?` steps from JSON-LD into plain `[String]`.
    /// Handles three common formats:
    ///  - `[String]`
    ///  - `[{"@type": "HowToStep", "text": "..."}]`
    ///  - `[{"@type": "HowToSection", "itemListElement": [...]}]`
    static func extractSteps(from raw: [Any]?) -> [String] {
        guard let raw else { return [] }
        var result: [String] = []
        for item in raw {
            if let s = item as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
            } else if let dict = item as? [String: Any] {
                if let text = dict["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { result.append(trimmed) }
                } else if let subItems = dict["itemListElement"] as? [[String: Any]] {
                    for sub in subItems {
                        if let text = sub["text"] as? String {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { result.append(trimmed) }
                        }
                    }
                }
            }
        }
        return result.map(cleanText)
    }

    // MARK: - Plain-Text Fallback

    private static let stepsHeadingPattern = #"^(instructions|directions|method|preparation|steps)( \(.*\))?:?$"#

    /// Last resort for pages with no recipe markup. Reads the page as lines and looks for an
    /// "Ingredients" heading with its list under it, and an "Instructions" or "Directions"
    /// heading with the steps under it.
    private static func extractFromPlainText(_ html: String) -> RecipeFetchResult? {
        let lines = plainTextLines(from: html)

        guard let ingredientsStart = lines.firstIndex(where: { isHeading($0, pattern: #"^ingredients?:?$"#) }) else {
            return nil
        }

        var ingredients: [String] = []
        var index = ingredientsStart + 1
        while index < lines.count, ingredients.count < 60 {
            let line = lines[index]
            if isHeading(line, pattern: stepsHeadingPattern) || isStopLine(line) { break }
            if line.count < 200 { ingredients.append(line) }
            index += 1
        }
        guard ingredients.count >= 2 else { return nil }

        var steps: [String] = []
        if let stepsStart = lines.firstIndex(where: { isHeading($0, pattern: stepsHeadingPattern) }) {
            var stepIndex = stepsStart + 1
            while stepIndex < lines.count, steps.count < 40 {
                let line = lines[stepIndex]
                if isStopLine(line) { break }
                // Real steps are sentences. Short lines without punctuation are usually page footers.
                if line.count > 20, let last = line.last, ".!?".contains(last) {
                    steps.append(line)
                }
                stepIndex += 1
            }
        }

        return RecipeFetchResult(
            title: plainTextTitle(html) ?? "Untitled Recipe",
            ingredients: ingredients,
            steps: steps.isEmpty ? nil : steps,
            totalMinutes: nil
        )
    }

    /// The page's visible text, one entry per line. Block tags become line breaks.
    private static func plainTextLines(from html: String) -> [String] {
        var s = html.replacingOccurrences(of: #"(?si)<(script|style)[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</?(p|li|ul|ol|div|h[1-6]|tr|section|article|header|footer)\b[^>]*>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return s
            .components(separatedBy: .newlines)
            .map { cleanText($0) }
            .filter { !$0.isEmpty }
    }

    private static func plainTextTitle(_ html: String) -> String? {
        // The <title> tag is usually the page's own name. Skip very long text, such as a browser warning.
        for pattern in [#"(?si)<title[^>]*>.*?</title>"#, #"(?si)<h1[^>]*>.*?</h1>"#] {
            guard let range = html.range(of: pattern, options: .regularExpression) else { continue }
            let inner = String(html[range]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let cleaned = cleanText(inner)
            if !cleaned.isEmpty, cleaned.count <= 120 { return cleaned }
        }
        return nil
    }

    private static func isHeading(_ line: String, pattern: String) -> Bool {
        line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Lines that start a section after the recipe, such as nutrition or comments.
    private static func isStopLine(_ line: String) -> Bool {
        line.range(
            of: #"^(nutrition|notes?|share|comments?|related|advertisement|recommended|you (may|might) (also )?like|more from|latest|watch|don'?t miss|sign up|subscribe|click here)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    // MARK: - HTML Fallback

    private static func extractFromHTML(_ doc: Document) throws -> RecipeFetchResult? {
        // Look for elements whose class or id contains "ingredient"
        let candidates = try doc.select("[class*=ingredient] li, [id*=ingredient] li, .wprm-recipe-ingredient")
        guard !candidates.isEmpty() else { return nil }

        var ingredients: [String] = []
        for el in candidates {
            let text = try el.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                ingredients.append(text)
            }
        }

        guard !ingredients.isEmpty else { return nil }

        // Try to get a title
        let titleEl = try doc.select("h2.wprm-recipe-name, .recipe-title, [class*=recipe] h1, [class*=recipe] h2").first()
        let title = try titleEl?.text() ?? doc.title()
        
        let stepsCandidates = try doc.select("[class*=instruction] li, [id*=instruction] li, .wprm-recipe-instruction")
        guard !stepsCandidates.isEmpty() else { return RecipeFetchResult(title: title, ingredients: ingredients, steps: nil, source: .html) }
        var steps: [String] = []
        for el in stepsCandidates {
            let text = try el.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                steps.append(text)
            }
        }

        return RecipeFetchResult(title: title, ingredients: ingredients, steps: steps, source: .html)
    }
}
