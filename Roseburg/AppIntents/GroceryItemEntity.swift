//
//  GroceryItemEntity.swift
//  Roseburg
//
//  Created by Justin Biggs on 4/19/26.
//

import AppIntents
import Foundation

/// An App Entity representing a single grocery item, exposing it to Siri, Shortcuts, and Apple Intelligence.
struct GroceryItemEntity: AppEntity {

    static var defaultQuery = GroceryItemEntityQuery()

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Grocery Item",
        numericFormat: "\(placeholder: .int) grocery items"
    )

    var id: String
    var name: String
    var quantity: String
    var category: String
    var isChecked: Bool

    var displayRepresentation: DisplayRepresentation {
        let subtitle = quantity.isEmpty ? category : "\(quantity) — \(category)"
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)"
        )
    }

    /// Creates an entity from a SwiftData GroceryItem.
    @MainActor
    init(from item: GroceryItem) {
        self.id = item.persistentModelID.hashValue.description
        self.name = item.name
        self.quantity = item.quantity
        self.category = item.category.displayName
        self.isChecked = item.isChecked
    }

    init(id: String, name: String, quantity: String, category: String, isChecked: Bool) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.category = category
        self.isChecked = isChecked
    }
}

// MARK: - Entity Query

struct GroceryItemEntityQuery: EntityQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [GroceryItemEntity] {
        let allItems = try GroceryDataStore.shared.fetchAllItems()
        return allItems
            .map { GroceryItemEntity(from: $0) }
            .filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [GroceryItemEntity] {
        let items = try GroceryDataStore.shared.fetchUncheckedItems()
        return items.map { GroceryItemEntity(from: $0) }
    }
}
