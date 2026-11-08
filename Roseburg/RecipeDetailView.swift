//
//  RecipeDetailView.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/26/26.
//

import SwiftUI
import UIKit

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Generable Types for Step-Ingredient Matching

@Generable
struct StepIngredients {
    @Guide(description: "The step number (1-based) from the recipe.")
    var stepNumber: Int
    
    @Guide(description: "The ingredient names from the recipe that are explicitly mentioned or used in this step. Only include ingredients that the step text directly references.")
    var ingredientNames: [String]
}

@Generable
struct AllStepIngredients {
    @Guide(description: "For each recipe step, the step number and the list of ingredients used in that step. Must include an entry for every step, even if ingredientNames is empty.")
    var steps: [StepIngredients]
}
#endif

// MARK: - View

struct RecipeDetailView: View {
    let recipe: Recipe
    @State private var stepIngredientMap: [Int: [GroceryItem]] = [:]
    @State private var isLoading = true
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true

    var body: some View {
        List {
            keepAwakeSection
            stepsSection
            ingredientsSection
            linkSection
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .task { await matchIngredientsToSteps() }
        .onAppear { applyIdleTimer() }
        .onChange(of: keepScreenAwake) { _, _ in applyIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Keep Awake

    private var keepAwakeSection: some View {
        Section {
            Toggle(isOn: $keepScreenAwake) {
                Label("Keep Screen Awake", systemImage: "sun.max")
            }
        } footer: {
            Text("While this recipe is open, the screen won't lock.")
        }
    }

    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
    }

    @ViewBuilder
    private var stepsSection: some View {
        if !recipe.steps.isEmpty {
            Section("Steps") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.tint)
                                .frame(width: 28, alignment: .center)
                            Text(Self.renderHTML(step))
                                .font(.body)
                        }

                        let matched = stepIngredientMap[index] ?? []
                        if isLoading {
                            ProgressView()
                                .padding(.leading, 40)
                        } else if !matched.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(matched, id: \.name) { item in
                                    HStack(spacing: 4) {
                                        Text("•")
                                        Text(item.name)
                                        if !item.quantity.isEmpty {
                                            Text("(\(item.quantity))")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 40)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } else {
            Section {
                ContentUnavailableView(
                    "No Steps Available",
                    systemImage: "list.number",
                    description: Text("This recipe didn't include step-by-step instructions.")
                )
            }
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach(recipe.items) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    if !item.quantity.isEmpty {
                        Text(item.quantity)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var linkSection: some View {
        Section {
            Link(destination: URL(string: recipe.url) ?? URL(string: "about:blank")!) {
                Label("View Original Recipe", systemImage: "safari")
            }
        }
    }

    // MARK: - Ingredient Matching

    private func matchIngredientsToSteps() async {
        defer { isLoading = false }

        #if canImport(FoundationModels)
        await matchWithAI()
        #else
        matchWithKeywords()
        #endif
    }

    #if canImport(FoundationModels)
    private func matchWithAI() async {
        let prompt = """
        You are a cooking assistant. I will give you a numbered ingredient list and numbered recipe steps.
        For EACH step, tell me which ingredients from the list are DIRECTLY used in that step.

        RULES:
        - Use the EXACT step number as shown.
        - Use ingredient names EXACTLY as they appear in the ingredient list.
        - ONLY include an ingredient if the step text explicitly names it or uses an obvious synonym.
        - If a step mentions "salmon" only list salmon, not the sauce ingredients.
        - If a step is about preheating or setup with no ingredients, return an empty list.
        - Do NOT shift or offset ingredient assignments between steps.

        INGREDIENT LIST:
        \(recipe.items.enumerated().map { "  \($0.offset + 1). \($0.element.name)" }.joined(separator: "\n"))

        RECIPE STEPS:
        \(recipe.steps.enumerated().map { "  Step \($0.offset + 1): \(Self.renderHTML($0.element))" }.joined(separator: "\n"))
        """

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: prompt,
                generating: AllStepIngredients.self
            )

            var map: [Int: [GroceryItem]] = [:]
            for stepResult in response.content.steps {
                let index = stepResult.stepNumber - 1
                guard index >= 0 && index < recipe.steps.count else { continue }
                let matched = stepResult.ingredientNames.compactMap { aiName in
                    recipe.items.first { item in
                        item.name.localizedCaseInsensitiveContains(aiName) ||
                        aiName.localizedCaseInsensitiveContains(item.name)
                    }
                }
                var seen = Set<String>()
                map[index] = matched.filter { seen.insert($0.name).inserted }
            }
            stepIngredientMap = map
        } catch {
            matchWithKeywords()
        }
    }
    #endif

    private func matchWithKeywords() {
        for (index, step) in recipe.steps.enumerated() {
            stepIngredientMap[index] = fallbackIngredientsUsed(in: step)
        }
    }

    /// Fallback keyword matcher when AI is unavailable.
    private func fallbackIngredientsUsed(in step: String) -> [GroceryItem] {
        let lowered = step.lowercased()
        return recipe.items.filter { item in
            let name = item.name.lowercased()
            if lowered.contains(name) { return true }
            let words = name.split(separator: " ").map(String.init)
            if words.count > 1 {
                return words.contains { $0.count >= 3 && lowered.contains($0) }
            }
            return false
        }
    }

    // MARK: - HTML Rendering

    private static func renderHTML(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#?\\w+;", with: "", options: .regularExpression)
        return text
    }
}
