//
//  ContentView.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/15/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: GroceryListViewModel?
    @State private var urlText = ""
    @FocusState private var isURLFieldFocused: Bool
    @State private var collapsedCategories: Set<AisleCategory> = []
    @State private var showingAddItem = false
    @State private var recipesItem: GroceryItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                urlInputBar
                contentArea
            }
            .navigationTitle("ListToShop")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingAddItem) {
                AddItemView { newItems in
                    for item in newItems {
                        viewModel?.addManualItem(name: item.name, quantity: item.quantity, category: item.category)
                    }
                }
            }
            .sheet(item: $recipesItem) { item in
                ItemRecipesView(item: item)
                    .presentationDetents([.height(recipesSheetHeight(for: item))])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = GroceryListViewModel(modelContext: modelContext)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .addRecipeFromShareExtension)) { notification in
                if let url = notification.userInfo?["url"] as? String {
                    Task { await viewModel?.addRecipe(url: url) }
                }
            }
        }
    }

    /// Height for the Recipes sheet: nav bar and padding plus one row per recipe, capped so long lists still scroll.
    private func recipesSheetHeight(for item: GroceryItem) -> CGFloat {
        let rows = max(item.recipes.count, 1)
        return min(140 + CGFloat(rows) * 52, 600)
    }

    // MARK: - URL Input

    private var urlInputBar: some View {
        HStack {
            TextField("Paste a recipe URL…", text: $urlText)
                .focused($isURLFieldFocused)
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            PasteButton(payloadType: String.self) { strings in
                // Clipboard links often arrive as plain text, not as URL items.
                guard let raw = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      raw.lowercased().hasPrefix("http"),
                      URL(string: raw) != nil else { return }
                urlText = ""
                isURLFieldFocused = false
                Task { await viewModel?.addRecipe(url: raw) }
            }
            .buttonBorderShape(.capsule)

            Button {
                guard !urlText.isEmpty else { return }
                let url = urlText
                urlText = ""
                isURLFieldFocused = false
                Task {
                        await viewModel?.addRecipe(url: url)
                }
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlText.isEmpty || (viewModel?.isLoading ?? false))
        }
        .padding()
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let vm = viewModel {
            if vm.isLoading {
                ProgressView("Fetching & categorizing…")
                    .padding()
                Spacer()
            } else if let error = vm.errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Dismiss") { vm.errorMessage = nil }
                }
            } else if vm.groceryItems.isEmpty {
                ContentUnavailableView(
                    "No Groceries Yet",
                    systemImage: "cart",
                    description: Text("Paste a recipe URL above to get started.")
                )
            } else {
                groceryList(vm: vm)
            }
        }
    }

    // MARK: - Grocery List

    private func groceryList(vm: GroceryListViewModel) -> some View {
        List {
            ForEach(vm.itemsByCategory, id: \.category) { section in
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { !collapsedCategories.contains(section.category) },
                            set: { isExpanded in
                                if isExpanded {
                                    collapsedCategories.remove(section.category)
                                } else {
                                    collapsedCategories.insert(section.category)
                                }
                            }
                        )
                    ) {
                        ForEach(section.items) { item in
                            groceryRow(item: item, vm: vm)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        vm.deleteItem(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } label: {
                        HStack {
                            Text(section.category.displayName)
                                .font(.headline)
                                .strikethrough(section.items.allSatisfy(\.isChecked))
                                .foregroundStyle(section.items.allSatisfy(\.isChecked) ? .secondary : .primary)
                            Spacer()
                            Text("\(section.items.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !vm.recipes.isEmpty {
                recipesSection(vm: vm)
            }
        }
    }

    // MARK: - Grocery Row

    private func groceryRow(item: GroceryItem, vm: GroceryListViewModel) -> some View {
        HStack {
            Button {
                vm.toggleItem(item)
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading) {
                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                if !item.quantity.isEmpty {
                    Text(item.quantity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Recipes") {
                recipesItem = item
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            vm.toggleItem(item)
        }
        .contextMenu {
            Menu("Change Aisle") {
                ForEach(AisleCategory.allCases) { category in
                    Button {
                        vm.setCategory(item, to: category)
                    } label: {
                        Label(category.displayName, systemImage: category == item.category ? "checkmark" : "circle")
                    }
                }
            }
        }
    }

    // MARK: - Recipes Section

    private func recipesSection(vm: GroceryListViewModel) -> some View {
        Section("Recipes") {
            ForEach(vm.recipes) { recipe in
                NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                    VStack(alignment: .leading) {
                        Text(recipe.title)
                            .font(.headline)
                        Text(recipe.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    vm.deleteRecipe(vm.recipes[index])
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingAddItem = true
            } label: {
                Label("Add Item", systemImage: "plus")
            }
        }
        if let vm = viewModel, !vm.groceryItems.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                ShareLink(item: vm.checklistText, subject: Text("Grocery List")) {
                    Label("Share Checklist", systemImage: "square.and.arrow.up")
                }
            }
        }
        if let vm = viewModel, !vm.groceryItems.isEmpty {
            ToolbarItem(placement: .cancellationAction) {
                Button("Clear All", role: .destructive) {
                    vm.clearAll()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                let allCategories = Set(vm.itemsByCategory.map(\.category))
                let allCollapsed = allCategories.isSubset(of: collapsedCategories)
                Button(allCollapsed ? "Expand All" : "Collapse All") {
                    withAnimation {
                        if allCollapsed {
                            collapsedCategories.removeAll()
                        } else {
                            collapsedCategories = allCategories
                        }
                    }
                }
            }
        }
        if let vm = viewModel, vm.groceryItems.contains(where: { $0.isChecked }) {
            ToolbarItem(placement: .confirmationAction) {
                Button("Clear Checked") {
                    vm.clearChecked()
                }
            }
        }
    }
}

// MARK: - Add Item Sheet

struct AddItemView: View {
    let onAdd: ([NewGroceryItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = ""
    @State private var pickedCategory: AisleCategory?
    @State private var isSorting = false

    /// Non-empty lines typed into the name field.
    private var lines: [String] {
        name.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Aisle guessed from the first typed line, used until the user picks one.
    private var guessedCategory: AisleCategory {
        guard let first = lines.first else { return .other }
        return IngredientCategorizer.categorizeWithKeywords([first]).first?.category ?? .other
    }

    /// Builds the items to add. A single line keeps the typed quantity. A pasted list is
    /// cleaned of bullets and checkboxes, then sorted into aisles (on-device model when available).
    private func buildItems() async -> [NewGroceryItem] {
        if lines.count <= 1 {
            guard let line = lines.first else { return [] }
            let guessed = IngredientCategorizer.categorizeWithKeywords([line]).first?.category ?? .other
            return [NewGroceryItem(
                name: line,
                quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
                category: pickedCategory ?? guessed
            )]
        }

        let cleaned = lines.map(Self.stripListMarkers).filter { !$0.isEmpty }
        let sorted = await IngredientCategorizer.sortList(cleaned)
        return sorted.map { entry in
            NewGroceryItem(name: entry.name, quantity: entry.quantity, category: pickedCategory ?? entry.category)
        }
    }

    private func submit() async {
        isSorting = true
        let items = await buildItems()
        isSorting = false
        onAdd(items)
        dismiss()
    }

    /// Removes bullets, checkboxes, and "1." numbering that people paste from lists.
    private static func stripListMarkers(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: #"^(\[[ xX]?\]|☐|☑|✅|[-•*·▪●])\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    private var categoryBinding: Binding<AisleCategory> {
        Binding(
            get: { pickedCategory ?? guessedCategory },
            set: { pickedCategory = $0 }
        )
    }

    private var canAdd: Bool {
        !lines.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item (e.g. Paper towels)", text: $name, axis: .vertical)
                        .lineLimit(1...8)
                    if lines.count <= 1 {
                        TextField("Quantity (optional)", text: $quantity)
                    }
                } footer: {
                    Text("Paste a list with one item per line. Items are sorted into aisles automatically.")
                }

                Section {
                    Picker("Aisle", selection: categoryBinding) {
                        ForEach(AisleCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSorting {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(!canAdd || isSorting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One item produced by the Add Item sheet, before it is merged into the list.
struct NewGroceryItem {
    let name: String
    let quantity: String
    let category: AisleCategory
}

// MARK: - Item Recipes Sheet

/// Shows which recipes call for a grocery item.
struct ItemRecipesView: View {
    let item: GroceryItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if item.recipes.isEmpty {
                    Text("Added by hand, not from a recipe.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Used in") {
                        ForEach(item.recipes.sorted { $0.dateAdded > $1.dateAdded }) { recipe in
                            Text(recipe.title)
                        }
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Recipe.self, GroceryItem.self], inMemory: true)
}
