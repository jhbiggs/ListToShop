//
//  RecipeFetcher.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/26/26.
//

import Foundation
import SwiftSoup

struct RecipeFetchResult {
    let title: String
    let ingredients: [String]
    let steps: [Any]?
}

enum RecipeFetchError: LocalizedError {
    case invalidURL
    case noRecipeFound
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL is not valid."
        case .noRecipeFound:
            return "No recipe found on this page."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

struct RecipeFetcher {

    /// Downloads the HTML at `urlString`, extracts the recipe title and ingredients.
    static func fetch(from urlString: String) async throws -> RecipeFetchResult {
        guard let url = URL(string: urlString) else {
            throw RecipeFetchError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw RecipeFetchError.noRecipeFound
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

        throw RecipeFetchError.noRecipeFound
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

        let title = dict["name"] as? String ?? "Untitled Recipe"
        guard let ingredients = dict["recipeIngredient"] as? [String], !ingredients.isEmpty else {
            return nil
        }
        
        let steps = dict["recipeInstructions"] as? [Any]

        print("Found recipe: \(title) with \(ingredients.count) ingredients and \(steps?.count ?? 0) steps")
        return RecipeFetchResult(title: title, ingredients: ingredients, steps: steps)
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
        return result
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
        guard !stepsCandidates.isEmpty() else { return RecipeFetchResult(title: title, ingredients: ingredients, steps: nil) }
        var steps: [String] = []
        for el in stepsCandidates {
            let text = try el.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                steps.append(text)
            }
        }

        return RecipeFetchResult(title: title, ingredients: ingredients, steps: steps)
    }
}
