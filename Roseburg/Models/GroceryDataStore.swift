//
//  GroceryDataStore.swift
//  Roseburg
//
//  Created by Justin Biggs on 4/19/26.
//

import Foundation
import SwiftData

/// A shared data store that bridges SwiftData with App Intents.
/// App Intents cannot use @Environment, so they access data through this singleton.
@MainActor
final class GroceryDataStore {

    static let shared = GroceryDataStore()

    private(set) var modelContainer: ModelContainer?

    private init() {}

    func configure(with container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Queries

    func fetchAllItems() throws -> [GroceryItem] {
        guard let context = modelContainer?.mainContext else { return [] }
        let descriptor = FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    func fetchUncheckedItems() throws -> [GroceryItem] {
        let all = try fetchAllItems()
        return all.filter { !$0.isChecked }
    }

    func fetchRecipes() throws -> [Recipe] {
        guard let context = modelContainer?.mainContext else { return [] }
        let descriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        return try context.fetch(descriptor)
    }

    func fetchItemsByCategory() throws -> [(category: AisleCategory, items: [GroceryItem])] {
        let items = try fetchUncheckedItems()
        let grouped = Dictionary(grouping: items) { $0.category }
        return AisleCategory.allCases.compactMap { cat in
            guard let catItems = grouped[cat], !catItems.isEmpty else { return nil }
            return (category: cat, items: catItems)
        }
    }
}
