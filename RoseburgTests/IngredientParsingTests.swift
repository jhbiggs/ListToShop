//
//  IngredientParsingTests.swift
//  RoseburgTests
//
//  Runs tricky ingredient lines, written the way recipe sites write them, through the
//  ingredient parser and checks the name and amount that would land on the grocery list.
//  Add a line to `IngredientCorpus.cases` whenever you spot a bad item in the app.
//

import XCTest
@testable import Roseburg
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One ingredient line plus what the grocery list should show for it.
/// `quantity: nil` means the amount isn't checked for that line.
struct IngredientCase {
    let line: String
    let name: String
    let quantity: String?
}

enum IngredientCorpus {
    static let cases: [IngredientCase] = [
        // Plain lines that should already work
        IngredientCase(line: "8 oz orecchiette", name: "Orecchiette", quantity: "8 oz"),
        IngredientCase(line: "⅓ cup water", name: "Water", quantity: "⅓ cup"),
        IngredientCase(line: "¼ teaspoon cayenne", name: "Cayenne", quantity: "¼ teaspoon"),
        IngredientCase(line: "1 tsp vanilla extract", name: "Vanilla extract", quantity: "1 tsp"),
        IngredientCase(line: "2 lbs chuck roast", name: "Chuck roast", quantity: "2 lbs"),
        IngredientCase(line: "10 ounces frozen peas", name: "Frozen peas", quantity: "10 ounces"),
        IngredientCase(line: "3 cups baby spinach", name: "Baby spinach", quantity: "3 cups"),
        IngredientCase(line: "6 slices bacon, chopped", name: "Bacon", quantity: "6 slices"),
        IngredientCase(line: "2 sprigs fresh rosemary", name: "Rosemary", quantity: "2 sprigs"),
        IngredientCase(line: "3 tbsp butter, divided", name: "Butter", quantity: "3 tbsp"),
        IngredientCase(line: "1/2 cup packed light brown sugar", name: "Light brown sugar", quantity: "1/2 cup"),
        IngredientCase(line: "3 tablespoons extra-virgin olive oil", name: "Olive oil", quantity: "3 tablespoons"),
        IngredientCase(line: "1 cup (240ml) heavy cream", name: "Heavy cream", quantity: "1 cup (240ml)"),
        IngredientCase(line: "1 package (8 oz) cream cheese, softened", name: "Cream cheese", quantity: "1 package (8 oz)"),

        // Capitalized and abbreviated units
        IngredientCase(line: "2 Tablespoons balsamic vinegar", name: "Balsamic vinegar", quantity: "2 Tablespoons"),
        IngredientCase(line: "1 Teaspoon kosher salt", name: "Kosher salt", quantity: "1 Teaspoon"),
        IngredientCase(line: "2 Cups chicken broth", name: "Chicken broth", quantity: "2 Cups"),
        IngredientCase(line: "1 Tbsp soy sauce", name: "Soy sauce", quantity: "1 Tbsp"),
        IngredientCase(line: "2 tbsp. olive oil", name: "Olive oil", quantity: "2 tbsp."),
        IngredientCase(line: "2 Tbs. olive oil", name: "Olive oil", quantity: "2 Tbs."),
        IngredientCase(line: "2 T olive oil", name: "Olive oil", quantity: "2 T"),
        IngredientCase(line: "1 t. ground cumin", name: "Cumin", quantity: "1 t."),
        IngredientCase(line: "2 c. shredded cheddar", name: "Cheddar", quantity: "2 c."),
        IngredientCase(line: "1 lb. ground beef", name: "Ground beef", quantity: "1 lb."),

        // Mixed numbers and ranges
        IngredientCase(line: "1 ½ cups all-purpose flour", name: "Flour", quantity: "1 ½ cups"),
        IngredientCase(line: "1½ cups sugar", name: "Sugar", quantity: "1½ cups"),
        IngredientCase(line: "1 1/2 cups milk", name: "Milk", quantity: "1 1/2 cups"),
        IngredientCase(line: "2 to 3 cups water", name: "Water", quantity: "2 to 3 cups"),
        IngredientCase(line: "1-2 jalapeños, seeded", name: "Jalapeños", quantity: "1-2"),

        // Metric
        IngredientCase(line: "200g plain flour", name: "Flour", quantity: "200g"),
        IngredientCase(line: "100 grams dark chocolate", name: "Dark chocolate", quantity: "100 grams"),
        IngredientCase(line: "1 kg potatoes", name: "Potatoes", quantity: "1 kg"),
        IngredientCase(line: "250 ml chicken stock", name: "Chicken stock", quantity: "250 ml"),

        // Can sizes in the middle
        IngredientCase(line: "2 (14.5-ounce) cans diced tomatoes", name: "Tomatoes", quantity: "2 (14.5-ounce) cans"),
        IngredientCase(line: "1 (15 oz) can black beans", name: "Black beans", quantity: "1 (15 oz) can"),
        IngredientCase(line: "1 14-ounce can coconut milk", name: "Coconut milk", quantity: nil),

        // Counts with no unit
        IngredientCase(line: "3 eggs", name: "Eggs", quantity: "3"),
        IngredientCase(line: "3 large eggs", name: "Eggs", quantity: "3 large"),
        IngredientCase(line: "1 large egg yolk", name: "Egg yolk", quantity: "1 large"),
        IngredientCase(line: "1/2 red onion, thinly sliced", name: "Red onion", quantity: "1/2"),
        IngredientCase(line: "1 medium yellow onion, diced", name: "Yellow onion", quantity: "1 medium"),
        IngredientCase(line: "4 boneless skinless chicken thighs", name: "Chicken thighs", quantity: "4"),
        IngredientCase(line: "2 cloves garlic, minced", name: "Garlic", quantity: "2 cloves"),

        // Units the parser doesn't know
        IngredientCase(line: "½ stick (4 tablespoons) unsalted butter", name: "Butter", quantity: "½ stick (4 tablespoons)"),
        IngredientCase(line: "1 envelope (1/4 oz) active dry yeast", name: "Active dry yeast", quantity: "1 envelope (1/4 oz)"),
        IngredientCase(line: "1 ear corn", name: "Corn", quantity: "1 ear"),
        IngredientCase(line: "1 head of garlic", name: "Garlic", quantity: "1 head"),

        // Wording around the food
        IngredientCase(line: "Salt and pepper, to taste", name: "Salt and pepper", quantity: ""),
        IngredientCase(line: "Kosher salt", name: "Kosher salt", quantity: ""),
        IngredientCase(line: "Juice of 1 lemon", name: "Lemon", quantity: nil),
        IngredientCase(line: "Zest of 1 orange", name: "Orange", quantity: nil),
        IngredientCase(line: "A pinch of red pepper flakes", name: "Red pepper flakes", quantity: nil),
        IngredientCase(line: "1 Tbsp. + 1 tsp. honey", name: "Honey", quantity: nil),
    ]
}

final class IngredientParsingTests: XCTestCase {

    /// The keyword parser: what devices without Apple Intelligence use, and the AI path's fallback.
    func testKeywordParser() {
        let cases = IngredientCorpus.cases
        let results = IngredientCategorizer.categorizeWithKeywords(cases.map(\.line))

        var rows: [String] = []
        var failed = 0
        for (testCase, result) in zip(cases, results) {
            let nameOK = IngredientChecks.same(result.name, testCase.name)
            let quantityOK = testCase.quantity.map { IngredientChecks.same(result.quantity, $0) } ?? true
            let ok = nameOK && quantityOK
            if !ok {
                failed += 1
                let expectedQuantity = testCase.quantity.map { ", amount \"\($0)\"" } ?? ""
                XCTFail("\"\(testCase.line)\" became name \"\(result.name)\", amount \"\(result.quantity)\". Expected name \"\(testCase.name)\"\(expectedQuantity).")
            }
            rows.append("\(ok ? "✅" : "❌") \(testCase.line)\n     → name: \(result.name) | amount: \(result.quantity)")
        }

        attachReport(
            "Keyword parser: \(cases.count - failed) of \(cases.count) lines correct\n\n" + rows.joined(separator: "\n"),
            named: "Keyword parser report"
        )
    }

    /// The Apple Intelligence parser, sent the whole list at once the way the app does.
    /// The model's answers vary a little between runs, so a single miss is worth re-running before fixing.
    func testAppleIntelligenceParser() async throws {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            throw XCTSkip("Apple Intelligence unavailable: \(String(describing: availability))")
        }

        let cases = IngredientCorpus.cases
        let lines = cases.map(\.line)
        let results = try await IngredientCategorizer.categorize(lines) as [(name: String, quantity: String, category: AisleCategory)]

        var rows: [String] = []
        if results.count != lines.count {
            XCTFail("Apple Intelligence returned \(results.count) items for \(lines.count) lines, so some ingredients were dropped or merged.")
            rows.append("⚠️ Returned \(results.count) items for \(lines.count) lines")
        }

        // Match by name rather than position, since the model can drop or reorder items.
        var failed = 0
        for testCase in cases {
            let match = results.first { IngredientChecks.loosely(testCase.name, matches: $0.name) }
            if let match {
                rows.append("✅ \(testCase.line)\n     → name: \(match.name) | amount: \(match.quantity) | aisle: \(match.category.rawValue)")
            } else {
                failed += 1
                XCTFail("Apple Intelligence: no item named like \"\(testCase.name)\" for \"\(testCase.line)\".")
                rows.append("❌ \(testCase.line)\n     → no item named like \"\(testCase.name)\"")
            }
        }

        // Names that kept part of the amount or lost letters, whichever line they came from.
        for result in results {
            if let first = result.name.first, first.isNumber {
                XCTFail("Apple Intelligence: name \"\(result.name)\" still has the amount in it.")
            }
            // Checked against every line, so a word that starts a word anywhere isn't flagged.
            if IngredientChecks.looksChopped(name: result.name, source: lines.joined(separator: "\n")) {
                XCTFail("Apple Intelligence: name \"\(result.name)\" lost letters from a word.")
            }
        }

        attachReport(
            "Apple Intelligence parser: \(cases.count - failed) of \(cases.count) lines found\n\n" + rows.joined(separator: "\n"),
            named: "Apple Intelligence parser report"
        )
        #else
        throw XCTSkip("FoundationModels isn't available in this SDK.")
        #endif
    }
}

// MARK: - Shared checks

enum IngredientChecks {

    /// Case-insensitive comparison that ignores extra spaces and a trailing period.
    static func same(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    /// True when one name contains the other, e.g. "Balsamic vinegar" and "balsamic vinegar of Modena".
    static func loosely(_ expected: String, matches actual: String) -> Bool {
        let e = normalize(expected), a = normalize(actual)
        guard !e.isEmpty, !a.isEmpty else { return false }
        return a.contains(e) || e.contains(a)
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// True when the name's first word only appears inside a longer word in the source line,
    /// like "ablespoons" from "Tablespoons" or "loves" from "Cloves".
    static func looksChopped(name: String, source: String) -> Bool {
        guard let first = name.lowercased().split(separator: " ").first.map(String.init),
              first.count >= 3 else { return false }
        let src = source.lowercased()
        guard src.contains(first) else { return false }  // reworded, so there's nothing to compare
        let pattern = "(^|[^\\p{L}])" + NSRegularExpression.escapedPattern(for: first)
        return src.range(of: pattern, options: .regularExpression) == nil
    }

    /// True when HTML tags or entities were left in text that should be plain.
    static func hasHTML(_ s: String) -> Bool {
        s.contains("&amp;") || s.contains("&#") || s.contains("&nbsp;") || s.contains("&quot;")
            || s.range(of: #"<[a-zA-Z/][^>]*>"#, options: .regularExpression) != nil
    }

    /// Describes what's wrong with one parsed ingredient line, or nil if it looks fine.
    static func issue(raw: String, name: String, quantity: String) -> String? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasHTML(line) { return "HTML left in the text" }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "empty name" }
        if let first = name.first, first.isNumber || "+&/".contains(first) {
            return "name \"\(name)\" still has the amount in it"
        }
        if name.lowercased().hasPrefix("of ") { return "name \"\(name)\" starts with \"of\"" }
        if looksChopped(name: name, source: line) { return "name \"\(name)\" lost letters from a word" }
        if let first = line.first, first.isNumber, quantity.isEmpty {
            return "amount not recognized (name \"\(name)\")"
        }
        return nil
    }
}

extension XCTestCase {
    /// Prints a report to the console and keeps it in the test results (Report navigator → this test).
    func attachReport(_ text: String, named name: String) {
        print("\n===== \(name) =====\n\(text)\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
