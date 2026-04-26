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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                urlInputBar
                contentArea
            }
            .navigationTitle("ShopZen")
            .toolbar { toolbarContent }
            .onAppear {
                if viewModel == nil {
                    viewModel = GroceryListViewModel(modelContext: modelContext)
                }
            }
        }
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
                        }
                    } label: {
                        HStack {
                            Text(section.category.displayName)
                                .font(.headline)
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

#Preview {
    ContentView()
        .modelContainer(for: [Recipe.self, GroceryItem.self], inMemory: true)
}
