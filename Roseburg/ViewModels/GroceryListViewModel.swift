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
            return (category: cat, items: items)
        }
    }

    // MARK: - Actions

    /// Fetches a recipe URL, extracts ingredients, categorizes them with Apple Intelligence, and saves everything.
    func addRecipe(url: String) async {
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
            let recipe = Recipe(url: url, title: result.title, rawIngredients: result.ingredients, steps: steps)
            modelContext.insert(recipe)

            // 4. Create GroceryItem models, merging duplicates by name
            //    First, group categorized items by name to merge within this recipe
            let grouped = Dictionary(grouping: categorized) { $0.name.lowercased() }
            let merged = grouped.map { (_, items) -> (name: String, quantity: String, category: AisleCategory) in
                let name = items.first!.name
                let category = items.first!.category
                let quantities = items.map(\.quantity).filter { !$0.isEmpty }
                let mergedQty = quantities.count > 1
                    ? QuantityMerger.merge(quantities)
                    : quantities.first ?? ""
                return (name: name, quantity: mergedQty, category: category)
            }

            // Then check against existing items in the store
            let allItemsDescriptor = FetchDescriptor<GroceryItem>()
            let allExisting = (try? modelContext.fetch(allItemsDescriptor)) ?? []

            for item in merged {
                if let existing = allExisting.first(where: { $0.name.lowercased() == item.name.lowercased() }) {
                    // Merge quantities across recipes
                    if !item.quantity.isEmpty {
                        let quantities = [existing.quantity, item.quantity].filter { !$0.isEmpty }
                        existing.quantity = QuantityMerger.merge(quantities)
                    }
                    recipe.items.append(existing)
                } else {
                    let groceryItem = GroceryItem(
                        name: item.name,
                        quantity: item.quantity,
                        category: item.category
                    )
                    groceryItem.recipe = recipe
                    recipe.items.append(groceryItem)
                    modelContext.insert(groceryItem)
                }
            }

            try modelContext.save()
            fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func deleteRecipe(_ recipe: Recipe) {
        modelContext.delete(recipe)
        try? modelContext.save()
        fetchAll()
    }

    func toggleItem(_ item: GroceryItem) {
        item.isChecked.toggle()
        try? modelContext.save()
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

    // MARK: - Private

    private func fetchAll() {
        let recipeDescriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        recipes = (try? modelContext.fetch(recipeDescriptor)) ?? []

        let itemDescriptor = FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\.name)])
        groceryItems = (try? modelContext.fetch(itemDescriptor)) ?? []
    }
}
