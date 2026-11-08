//
//  IngredientCategorizer.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/26/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Generable Output Types

/// A single categorized ingredient returned by the on-device LLM.
@Generable
struct CategorizedIngredient {
    @Guide(description: "The short, cleaned-up ingredient name (e.g. 'chicken breast', 'olive oil').")
    var name: String

    @Guide(description: "The quantity and unit as written in the recipe (e.g. '2 lbs', '1 cup'). Empty string if not specified.")
    var quantity: String

    @Guide(description: "The grocery store aisle category. Must be exactly one of: produce, dairy, meat, bakery, frozen, canned, spices, beverages, snacks, condiments, other.")
    var category: String
}

/// The full structured response from the model.
@Generable
struct CategorizedIngredientList {
    @Guide(description: "Array of ingredients, each with a name, quantity, and aisle category.")
    var ingredients: [CategorizedIngredient]
}
#endif

// MARK: - Categorizer Service

struct IngredientCategorizer {

    // MARK: - Public API

    #if canImport(FoundationModels)
    /// Uses the on-device Apple Intelligence model to parse raw ingredient strings
    /// into structured, categorized grocery items.
    static func categorize(_ rawIngredients: [String]) async throws -> [(name: String, quantity: String, category: AisleCategory)] {

        let session = LanguageModelSession()

        let ingredientList = rawIngredients
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        You are a grocery store assistant. For each ingredient below, extract:
        1. A short, clean ingredient name — just the food item, no quantities, units, or preparation notes. For example: "olive oil", "parsley", "shrimp", "orzo".
        2. The quantity and unit exactly as written (e.g. "2 lbs", "1/4 cup", "4 tablespoons"). Use empty string if not specified.
        3. The grocery store aisle category.

        IMPORTANT: The name must NEVER start with a period, unit abbreviation, or number. Only the food name.
        Never remove letters from the start of a word: "Cloves garlic" is "garlic" with a 3-clove quantity, not "loves garlic".

        Ingredients:
        \(ingredientList)
        """

        let response = try await session.respond(
            to: prompt,
            generating: CategorizedIngredientList.self
        )

        return response.content.ingredients.map { item in
            let category = AisleCategory(rawValue: item.category.lowercased()) ?? .other
            let cleanedName = repairName(cleanAIName(item.name), rawIngredients: rawIngredients)
            return (name: cleanedName, quantity: item.quantity, category: category)
        }
    }
    #endif

    /// Cleans up AI-generated ingredient names that may have leading punctuation,
    /// unit abbreviations, or other artifacts.
    private static func cleanAIName(_ name: String) -> String {
        var cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading patterns like ". ", "C. ", "Pt. ", "Tbsp. ", etc.
        let leadingJunkPattern = #"^(?:[A-Za-z]{0,4}\.\s*|[\.\,\-\;\:]+\s*)"#
        if let range = cleaned.range(of: leadingJunkPattern, options: .regularExpression) {
            cleaned = String(cleaned[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Strip leading "and " (e.g. "and shrimp")
        if cleaned.lowercased().hasPrefix("and ") {
            cleaned = String(cleaned.dropFirst(4))
        }

        // Capitalize first letter
        if let first = cleaned.first {
            cleaned = first.uppercased() + cleaned.dropFirst()
        }

        return cleaned.isEmpty ? name : cleaned
    }

    /// The model sometimes drops a leading letter ("Cloves garlic" → "Loves garlic").
    /// If the name only appears inside a longer word in the source text, use the
    /// keyword-cleaned name from that source line instead.
    private static func repairName(_ name: String, rawIngredients: [String]) -> String {
        // Check the first word only, since the model may also add or drop other words.
        guard let firstWord = name.lowercased().split(separator: " ").first.map(String.init),
              firstWord.count >= 3 else { return name }

        let escaped = NSRegularExpression.escapedPattern(for: firstWord)
        let startsAWord = rawIngredients.contains { raw in
            raw.lowercased().range(of: "\\b\(escaped)", options: .regularExpression) != nil
        }
        if startsAWord { return name }

        guard let source = rawIngredients.first(where: { $0.lowercased().contains(firstWord) }) else {
            return name
        }
        return categorizeWithKeywords([source]).first?.name ?? name
    }

    /// Keyword-based categorizer — used as fallback or on non-AI devices.
    static func categorize(_ ingredients: [String]) -> [(name: String, quantity: String, category: AisleCategory)] {
        return categorizeWithKeywords(ingredients)
    }

    /// Sorts a pasted grocery list into aisles. Uses the on-device model when available,
    /// and falls back to keyword matching otherwise.
    static func sortList(_ lines: [String]) async -> [(name: String, quantity: String, category: AisleCategory)] {
        #if canImport(FoundationModels)
        do {
            return try await categorize(lines) as [(name: String, quantity: String, category: AisleCategory)]
        } catch {
            return categorizeWithKeywords(lines)
        }
        #else
        return categorizeWithKeywords(lines)
        #endif
    }

    /// Explicit keyword-based categorizer (avoids ambiguity with async overload).
    static func categorizeWithKeywords(_ ingredients: [String]) -> [(name: String, quantity: String, category: AisleCategory)] {
        return ingredients.map { raw in
            let (quantity, name) = splitQuantityAndName(raw)
            let simplified = simplifyName(name)
            let category = categorize(ingredient: simplified)
            return (name: simplified, quantity: quantity, category: category)
        }
    }

    // MARK: - Keyword-based categorization

    private static let categoryKeywords: [(AisleCategory, [String])] = [
        (.produce, [
            "lettuce", "tomato", "tomatoes", "onion", "garlic", "pepper", "bell pepper",
            "carrot", "celery", "potato", "potatoes", "apple", "banana", "lemon", "lime",
            "avocado", "spinach", "kale", "cucumber", "broccoli", "mushroom", "mushrooms",
            "ginger", "cilantro", "parsley", "basil", "mint", "thyme", "rosemary",
            "oregano", "dill", "chive", "scallion", "green onion", "shallot", "leek",
            "zucchini", "squash", "cabbage", "cauliflower", "asparagus", "corn",
            "peas", "green bean", "jalapeño", "jalapeno", "serrano", "habanero",
            "beet", "radish", "turnip", "sweet potato", "yam", "eggplant",
            "orange", "grape", "strawberry", "blueberry", "raspberry", "blackberry",
            "peach", "pear", "plum", "mango", "pineapple", "watermelon", "melon",
            "cherry", "cranberry", "pomegranate", "fig", "date", "coconut",
        ]),
        (.dairy, [
            "milk", "cheese", "butter", "cream", "yogurt", "yoghurt", "egg", "eggs",
            "sour cream", "cream cheese", "cottage cheese", "ricotta", "mozzarella",
            "parmesan", "cheddar", "gouda", "brie", "feta", "provolone",
            "half and half", "half-and-half", "whipping cream", "heavy cream",
            "buttermilk", "ghee",
        ]),
        (.meat, [
            "chicken", "beef", "pork", "turkey", "bacon", "sausage", "steak",
            "ground beef", "ground turkey", "ground pork", "lamb", "veal",
            "fish", "salmon", "shrimp", "tuna", "cod", "tilapia", "halibut",
            "crab", "lobster", "scallop", "clam", "mussel", "anchovy", "anchovies",
            "prosciutto", "ham", "pepperoni", "salami", "chorizo",
            "chicken breast", "chicken thigh", "drumstick", "wing",
        ]),
        (.bakery, [
            "bread", "tortilla", "bun", "buns", "roll", "rolls", "pita", "naan",
            "bagel", "croissant", "muffin", "biscuit", "cornbread", "flatbread",
            "hamburger bun", "hot dog bun", "english muffin", "ciabatta", "sourdough",
        ]),
        (.frozen, [
            "frozen", "ice cream", "frozen pizza", "frozen vegetables",
            "frozen fruit", "frozen dinner", "popsicle",
        ]),
        (.canned, [
            "canned", "beans", "black beans", "kidney beans", "pinto beans",
            "chickpea", "chickpeas", "garbanzo", "lentil", "lentils",
            "tomato sauce", "tomato paste", "diced tomatoes", "crushed tomatoes",
            "coconut milk", "broth", "stock", "chicken broth", "beef broth",
            "vegetable broth", "chicken stock", "beef stock",
        ]),
        (.spices, [
            "salt", "pepper", "black pepper", "cumin", "paprika", "cinnamon",
            "nutmeg", "turmeric", "chili powder", "cayenne", "curry powder",
            "garlic powder", "onion powder", "bay leaf", "bay leaves",
            "red pepper flakes", "crushed red pepper", "clove", "cloves",
            "coriander", "cardamom", "allspice", "saffron", "fennel seed",
            "sesame seed", "poppy seed", "italian seasoning", "taco seasoning",
            "seasoning", "dried oregano", "dried basil", "dried thyme",
        ]),
        (.condiments, [
            "ketchup", "mustard", "mayo", "mayonnaise", "relish",
            "hot sauce", "sriracha", "soy sauce", "worcestershire",
            "barbecue sauce", "bbq sauce", "teriyaki", "hoisin",
            "salsa", "pesto", "tahini", "ranch", "dressing",
            "vinaigrette", "jam", "jelly", "peanut butter", "almond butter",
            "nutella", "maple syrup", "agave",
        ]),
        (.beverages, [
            "water", "juice", "soda", "coffee", "tea", "wine", "beer",
            "sparkling water", "seltzer", "lemonade", "orange juice",
            "apple juice", "kombucha", "smoothie",
        ]),
        (.snacks, [
            "chips", "crackers", "pretzels", "popcorn", "nuts", "almonds",
            "walnuts", "pecans", "cashews", "peanuts", "trail mix",
            "granola", "granola bar", "protein bar", "cookies", "candy",
            "chocolate", "dried fruit", "raisins",
        ]),
    ]

    private static let pantryKeywords: [String] = [
        "flour", "sugar", "brown sugar", "powdered sugar", "baking soda",
        "baking powder", "yeast", "cornstarch", "vanilla", "vanilla extract",
        "cocoa", "cocoa powder", "chocolate chips", "oil", "olive oil",
        "vegetable oil", "canola oil", "coconut oil", "sesame oil",
        "vinegar", "apple cider vinegar", "balsamic vinegar", "red wine vinegar",
        "white vinegar", "rice vinegar", "honey", "syrup", "molasses",
        "rice", "pasta", "noodle", "noodles", "spaghetti", "penne",
        "macaroni", "linguine", "fettuccine", "orzo", "couscous", "quinoa",
        "oats", "oatmeal", "cereal", "panko", "breadcrumbs",
    ]

    private static func categorize(ingredient: String) -> AisleCategory {
        let lowered = ingredient.lowercased()

        for (category, keywords) in categoryKeywords {
            if keywords.contains(where: { lowered.contains($0) }) {
                return category
            }
        }

        if pantryKeywords.contains(where: { lowered.contains($0) }) {
            return .other
        }

        return .other
    }

    // MARK: - Quantity / Name Parsing

    private static func splitQuantityAndName(_ raw: String) -> (quantity: String, name: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let quantityPattern = #"^([\d½¼¾⅓⅔⅛/.\-–]+\s*(?:cups?|C|c|tablespoons?|tbsp|T|teaspoons?|tsp|t|ounces?|oz|pounds?|lbs?|lb|gallons?|gal|quarts?|qt|pints?|pt|liters?|ml|cloves?|cans?|jars?|bags?|boxes?|packages?|bunch(?:es)?|heads?|stalks?|slices?|pieces?|pinch(?:es)?|dash(?:es)?|handfuls?|sprigs?|large|medium|small|whole)\.?[\s,]*(?:\([^)]*\)\s*)?)"#

        if let range = trimmed.range(of: quantityPattern, options: .regularExpression, range: trimmed.startIndex..<trimmed.endIndex) {
            let quantity = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ","))
            let name = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ","))
            if !name.isEmpty {
                return (quantity, name)
            }
        }

        return ("", trimmed)
    }

    // MARK: - Name Simplification

    static func simplifyName(_ raw: String) -> String {
        var name = raw.lowercased()

        // Strip leading periods, unit abbreviations left over from quantity parsing
        // e.g. ". olive oil", "C. orzo", "Pt. grape tomatoes"
        name = name.replacingOccurrences(
            of: #"^(?:[a-z]{0,4}\.\s*|[\.\,\;\:]+\s*)+"#,
            with: "",
            options: .regularExpression
        )

        // Strip leading "and " (e.g. "and shrimp")
        if name.hasPrefix("and ") {
            name = String(name.dropFirst(4))
        }

        if let commaRange = name.range(of: #",\s*(for\s|to\s|or\s|plus\s|divided|optional|if\s|as\s|at\s|such\s).*"#, options: .regularExpression) {
            name = String(name[..<commaRange.lowerBound])
        }

        name = name.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)

        let modifiers = [
            "freshly", "fresh", "finely", "thinly", "thickly", "roughly", "coarsely",
            "lightly", "firmly", "well", "very",
            "chopped", "diced", "minced", "sliced", "grated", "shredded", "crushed",
            "ground", "crumbled", "julienned", "cubed", "halved", "quartered",
            "peeled", "seeded", "deveined", "deboned", "boneless", "skinless",
            "trimmed", "cored", "pitted", "stemmed", "shelled", "husked",
            "melted", "softened", "chilled", "cooled", "warmed", "toasted",
            "roasted", "sautéed", "sauteed", "blanched", "steamed", "boiled",
            "fried", "baked", "grilled", "broiled", "smoked", "cured", "dried",
            "packed", "sifted", "drained", "rinsed", "squeezed", "pressed",
            "extra-virgin", "extra virgin", "low-sodium", "low sodium",
            "low-fat", "low fat", "fat-free", "nonfat", "whole",
            "unsalted", "salted", "unsweetened", "sweetened",
            "raw", "cooked", "uncooked", "prepared", "store-bought",
            "organic", "all-purpose", "all purpose", "self-rising",
            "large", "medium", "small", "thin", "thick",
            "plain", "pure", "distilled", "filtered", "cold", "warm", "hot", "room temperature",
        ]

        for modifier in modifiers {
            name = name.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: modifier))\\b",
                with: "",
                options: .regularExpression
            )
        }

        name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",-–— "))

        if let first = name.first {
            name = first.uppercased() + name.dropFirst()
        }

        return name
    }
}

// MARK: - Duplicate Detection

#if canImport(FoundationModels)
@Generable
struct IngredientMatch {
    @Guide(description: "A name copied exactly from the NEW list.")
    var newName: String

    @Guide(description: "A name copied exactly from the EXISTING list that is the same grocery product, or an empty string if there is none.")
    var existingName: String
}

@Generable
struct IngredientMatchList {
    @Guide(description: "One entry for every name in the NEW list.")
    var matches: [IngredientMatch]
}
#endif

/// Decides when two ingredient names refer to the same grocery item.
/// `key(for:)` catches exact duplicates deterministically. `matchSynonyms` asks the
/// on-device model about near-duplicates such as "Scallions" and "Green onions".
enum IngredientMatcher {

    /// Canonical dictionary key: lowercased, accent-free, punctuation and parentheticals
    /// removed, and each word singularized. "Tomatoes", "tomato" and "Tomato (diced)" share a key.
    static func key(for name: String) -> String {
        var s = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
        let words = s.split(whereSeparator: { $0.isWhitespace }).map { singularize(String($0)) }
        let result = words.joined(separator: " ")
        return result.isEmpty ? name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) : result
    }

    private static func singularize(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("xes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ss") || word.hasSuffix("us") || word.hasSuffix("is") { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    /// Returns a map from each new name to the existing name it duplicates.
    /// Returns an empty map when the model is unavailable or finds nothing.
    static func matchSynonyms(newNames: [String], existingNames: [String]) async -> [String: String] {
        #if canImport(FoundationModels)
        guard !newNames.isEmpty, !existingNames.isEmpty else { return [:] }

        var existingByKey: [String: String] = [:]
        for name in existingNames where existingByKey[key(for: name)] == nil {
            existingByKey[key(for: name)] = name
        }
        var newByKey: [String: String] = [:]
        for name in newNames where newByKey[key(for: name)] == nil {
            newByKey[key(for: name)] = name
        }

        let prompt = """
        You are checking a grocery list for duplicates. Below are EXISTING items and NEW items.
        For each NEW item, return the EXISTING item it is the same grocery product as, or an empty string if none is.
        Ignore quantities, preparation words, and capitalization.
        Same product examples: "Garlic" = "garlic cloves"; "Scallions" = "Green onions".
        Different product examples: "Butter" is not "Peanut butter"; "Lime" is not "Lime juice"; "Chicken" is not "Chicken broth".
        Only match when they are truly the same product. When unsure, return an empty string.

        EXISTING:
        \(existingNames.map { "  - \($0)" }.joined(separator: "\n"))

        NEW:
        \(newNames.map { "  - \($0)" }.joined(separator: "\n"))
        """

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt, generating: IngredientMatchList.self)

            var result: [String: String] = [:]
            for match in response.content.matches {
                let existingKey = key(for: match.existingName)
                let newKey = key(for: match.newName)
                guard !existingKey.isEmpty,
                      let existingOriginal = existingByKey[existingKey],
                      let newOriginal = newByKey[newKey] else { continue }
                result[newOriginal] = existingOriginal
            }
            return result
        } catch {
            return [:]
        }
        #else
        return [:]
        #endif
    }
}
