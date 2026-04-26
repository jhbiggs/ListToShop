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
        1. A short, clean ingredient name (no quantities or preparation notes).
        2. The quantity and unit exactly as written (or empty string if none).

        Ingredients:
        \(ingredientList)
        """

        let response = try await session.respond(
            to: prompt,
            generating: CategorizedIngredientList.self
        )

        return response.content.ingredients.map { item in
            let category = AisleCategory(rawValue: item.category.lowercased()) ?? .other
            return (name: item.name, quantity: item.quantity, category: category)
        }
    }
    #endif

    /// Keyword-based categorizer — used as fallback or on non-AI devices.
    static func categorize(_ ingredients: [String]) -> [(name: String, quantity: String, category: AisleCategory)] {
        return categorizeWithKeywords(ingredients)
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

        let quantityPattern = #"^([\d½¼¾⅓⅔⅛/.\-–]+\s*(?:cups?|tablespoons?|tbsp|teaspoons?|tsp|ounces?|oz|pounds?|lbs?|gallons?|quarts?|pints?|liters?|ml|cloves?|cans?|jars?|bags?|boxes?|packages?|bunch(?:es)?|heads?|stalks?|slices?|pieces?|pinch(?:es)?|dash(?:es)?|handfuls?|sprigs?|large|medium|small|whole)?[\s,]*(?:\([^)]*\)\s*)?)"#

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
