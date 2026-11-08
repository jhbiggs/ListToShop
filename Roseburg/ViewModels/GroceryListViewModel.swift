//
//  GroceryListViewModel.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/26/26.
//

import Foundation
import SwiftData
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class GroceryListViewModel {

    var recipes: [Recipe] = []
    var groceryItems: [GroceryItem] = []
    var isLoading = false
    var errorMessage: String?

    private var modelContext: ModelContext

    /// One ingredient from a recipe, after categorizing and before it is matched to the list.
    private struct Incoming {
        var name: String
        var category: AisleCategory
        var quantities: [String]
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchAll()
    }

    // MARK: - Computed

    /// Groups all grocery items by aisle category for display.
    var itemsByCategory: [(category: AisleCategory, items: [GroceryItem])] {
        let grouped = Dictionary(grouping: groceryItems) { $0.category }
        return AisleCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            // Still-needed items first; checked items drop to the bottom of their aisle.
            let sorted = items.sorted { a, b in
                a.isChecked != b.isChecked ? !a.isChecked : a.name < b.name
            }
            return (category: cat, items: sorted)
        }
    }

    /// Plain-text checklist for sharing to Notes. ☐ still needed, ☑ already in the cart.
    var checklistText: String {
        var lines = ["Grocery List", ""]
        for section in itemsByCategory {
            lines.append(section.category.displayName)
            for item in section.items {
                let box = item.isChecked ? "☑" : "☐"
                let qty = item.quantity.isEmpty ? "" : " (\(item.quantity))"
                lines.append("\(box) \(item.name)\(qty)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Actions

    /// Fetches a recipe URL, extracts ingredients, categorizes them with Apple Intelligence, and saves everything.
    func addRecipe(url rawURL: String) async {
        // Unwrap Facebook link redirects so we fetch and store the real recipe page.
        let url = RecipeFetcher.unwrapRedirect(rawURL)
        isLoading = true
        errorMessage = nil

        do {
            // 1. Fetch & parse the recipe page
            let result = try await RecipeFetcher.fetch(from: url)

            // 2. Categorize ingredients (AI if available, keyword fallback otherwise)
            #if canImport(FoundationModels)
            let categorized: [(name: String, quantity: String, category: AisleCategory)]
            do {
                categorized = try await IngredientCategorizer.categorize(result.ingredients) as [(name: String, quantity: String, category: AisleCategory)]
            } catch {
                // AI unavailable — fall back to keyword categorizer
                let fallback: [String] = result.ingredients
                categorized = IngredientCategorizer.categorizeWithKeywords(fallback)
            }
            #else
            let categorized = IngredientCategorizer.categorize(result.ingredients)
            #endif

            // 3. Create the Recipe model
            let steps = RecipeFetcher.extractSteps(from: result.steps)
            // Use the page's time when it has one; otherwise ask the on-device model.
            var totalMinutes = result.totalMinutes
            var timeIsEstimated = false
            if totalMinutes == nil {
                totalMinutes = await RecipeTimeEstimator.estimateMinutes(
                    title: result.title,
                    ingredients: result.ingredients,
                    steps: steps
                )
                timeIsEstimated = totalMinutes != nil
            }

            let recipe = Recipe(
                url: url,
                title: result.title,
                rawIngredients: result.ingredients,
                steps: steps,
                totalMinutes: totalMinutes
            )
            recipe.timeIsEstimated = timeIsEstimated
            modelContext.insert(recipe)

            // 4. Collect this recipe's ingredients in a dictionary keyed by canonical name,
            //    so "Tomatoes" and "tomato" from the same recipe land in one entry.
            var incoming: [String: Incoming] = [:]
            for item in categorized {
                let key = IngredientMatcher.key(for: item.name)
                guard !key.isEmpty else { continue }
                var entry = incoming[key] ?? Incoming(name: item.name, category: item.category, quantities: [])
                if !item.quantity.isEmpty {
                    entry.quantities.append(item.quantity)
                }
                incoming[key] = entry
            }

            // 5. Index the existing list the same way.
            let existingItems = (try? modelContext.fetch(FetchDescriptor<GroceryItem>())) ?? []
            var existing: [String: GroceryItem] = [:]
            for item in existingItems {
                let key = IngredientMatcher.key(for: item.name)
                if existing[key] == nil {
                    existing[key] = item
                }
            }

            // 6. Names with no exact match may still be the same product ("Scallions" vs "Green onions").
            //    Ask the on-device model about just those.
            var aliases: [String: String] = [:]  // incoming key → existing key
            let unmatchedKeys = incoming.keys.filter { existing[$0] == nil }
            if !unmatchedKeys.isEmpty, !existing.isEmpty {
                let newNames = unmatchedKeys.compactMap { incoming[$0]?.name }
                let existingNames = existing.values.map(\.name)
                let matches = await IngredientMatcher.matchSynonyms(newNames: newNames, existingNames: existingNames)
                for (newName, existingName) in matches {
                    aliases[IngredientMatcher.key(for: newName)] = IngredientMatcher.key(for: existingName)
                }
            }

            // 7. Fold aliased entries into their targets.
            var merged: [String: Incoming] = [:]
            for (key, entry) in incoming {
                let target = aliases[key] ?? key
                if var current = merged[target] {
                    current.quantities += entry.quantities
                    merged[target] = current
                } else {
                    merged[target] = entry
                }
            }

            // 8. Update existing items or create new ones.
            for (key, entry) in merged {
                let quantity = Self.mergeQuantities(entry.quantities)
                if let item = existing[key] {
                    item.quantity = Self.mergeQuantities([item.quantity, quantity])
                    item.recipes.append(recipe)
                } else {
                    let item = GroceryItem(
                        name: entry.name,
                        quantity: quantity,
                        category: entry.category,
                        recipes: [recipe]
                    )
                    modelContext.insert(item)
                }
            }

            try modelContext.save()
            fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Adds an item by hand. If the list already has the same item, its quantity is combined and it is unchecked.
    func addManualItem(name: String, quantity: String, category: AisleCategory) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = IngredientMatcher.key(for: trimmedName)
        guard !key.isEmpty else { return }

        if let item = groceryItems.first(where: { IngredientMatcher.key(for: $0.name) == key }) {
            item.quantity = Self.mergeQuantities([item.quantity, trimmedQuantity])
            item.isChecked = false
        } else {
            let displayName = trimmedName.prefix(1).uppercased() + trimmedName.dropFirst()
            modelContext.insert(GroceryItem(name: displayName, quantity: trimmedQuantity, category: category))
        }
        try? modelContext.save()
        fetchAll()
    }

    func deleteRecipe(_ recipe: Recipe) {
        let linkedItems = recipe.items
        modelContext.delete(recipe)
        // Keep shared items that another recipe or a manual entry still needs.
        for item in linkedItems where item.recipes.allSatisfy({ $0 === recipe }) {
            modelContext.delete(item)
        }
        try? modelContext.save()
        fetchAll()
    }

    func deleteItem(_ item: GroceryItem) {
        modelContext.delete(item)
        try? modelContext.save()
        fetchAll()
    }

    func toggleItem(_ item: GroceryItem) {
        item.isChecked.toggle()
        try? modelContext.save()
    }

    func setCategory(_ item: GroceryItem, to category: AisleCategory) {
        item.category = category
        try? modelContext.save()
        fetchAll()
    }

    func clearChecked() {
        for item in groceryItems where item.isChecked {
            modelContext.delete(item)
        }
        try? modelContext.save()
        fetchAll()
    }

    func clearAll() {
        for recipe in recipes {
            modelContext.delete(recipe)
        }
        for item in groceryItems {
            modelContext.delete(item)
        }
        try? modelContext.save()
        fetchAll()
    }

    // MARK: - Timing

    /// The meal time's hour and minute applied to today, so only the time of day matters.
    func mealDate(for mealTime: Date) -> Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: mealTime)
        return Calendar.current.date(
            bySettingHour: parts.hour ?? 18,
            minute: parts.minute ?? 0,
            second: 0,
            of: .now
        ) ?? .now
    }

    /// Asks the on-device model for a time for a saved recipe that has none.
    func estimateTime(for recipe: Recipe) async {
        guard let minutes = await RecipeTimeEstimator.estimateMinutes(
            title: recipe.title,
            ingredients: recipe.rawIngredients,
            steps: recipe.steps
        ) else { return }
        recipe.totalMinutes = minutes
        recipe.timeIsEstimated = true
        try? modelContext.save()
        fetchAll()
    }

    /// Saves a time the user typed in. Passing nil clears it.
    func setTime(for recipe: Recipe, minutes: Int?) {
        recipe.totalMinutes = minutes
        recipe.timeIsEstimated = false
        try? modelContext.save()
        fetchAll()
    }

    /// When to start this recipe so it finishes at the meal time. Nil if the page gave no time.
    func suggestedStart(for recipe: Recipe, mealTime: Date) -> Date? {
        guard let minutes = recipe.totalMinutes else { return nil }
        return mealDate(for: mealTime).addingTimeInterval(-Double(minutes) * 60)
    }

    /// When to begin cooking: the start time of the longest recipe in the set.
    func startCookingBy(mealTime: Date) -> Date? {
        guard let longest = recipes.compactMap(\.totalMinutes).max() else { return nil }
        return mealDate(for: mealTime).addingTimeInterval(-Double(longest) * 60)
    }

    // MARK: - Private

    /// Merges quantity strings, ignoring empty ones.
    private static func mergeQuantities(_ quantities: [String]) -> String {
        let nonEmpty = quantities.filter { !$0.isEmpty }
        if nonEmpty.count > 1 {
            return QuantityMerger.merge(nonEmpty)
        }
        return nonEmpty.first ?? ""
    }

    private func fetchAll() {
        let recipeDescriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        recipes = (try? modelContext.fetch(recipeDescriptor)) ?? []

        let itemDescriptor = FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\.name)])
        groceryItems = (try? modelContext.fetch(itemDescriptor)) ?? []
    }
}
