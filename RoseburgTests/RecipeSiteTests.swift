//
//  RecipeSiteTests.swift
//  RoseburgTests
//
//  Fetches real recipe pages with the app's RecipeFetcher and reports which ones fail.
//  Needs a network connection. Results change as sites change, so treat this as a
//  diagnostic run rather than a test that must stay green.
//
//  To test a recipe that misbehaved in the app, add its URL to `RecipeSiteCorpus.sites`.
//

import XCTest
@testable import Roseburg

struct RecipeTestSite: Sendable {
    let url: String
    let note: String
    /// False for pages that shouldn't have a recipe, to check the app fails cleanly.
    var expectsRecipe: Bool = true
}

enum RecipeSiteCorpus {
    static let sites: [RecipeTestSite] = [
        // Big publishers
        RecipeTestSite(url: "https://www.allrecipes.com/recipe/8691/chicken-enchiladas-i/", note: "Allrecipes"),
        RecipeTestSite(url: "https://www.seriouseats.com/tamarind-braised-beef-short-ribs-recipe-11875259", note: "Serious Eats"),
        RecipeTestSite(url: "https://www.foodnetwork.com/recipes/ina-garten/perfect-roast-chicken-recipe-1940592", note: "Food Network"),
        RecipeTestSite(url: "https://www.foodnetwork.com/recipes/ina-garten/engagement-roast-chicken-recipe-1948980?soc=socialfnvideo", note: "Food Network, link with tracking parameter"),
        RecipeTestSite(url: "https://www.foodnetwork.com/recipes/orecchiette-sausage-and-broccoli-rabe-2109213", note: "Food Network"),
        RecipeTestSite(url: "https://www.bonappetit.com/recipe/bas-best-chocolate-chip-cookies", note: "Bon Appétit"),
        RecipeTestSite(url: "https://www.tasteofhome.com/recipes/braised-short-ribs-with-gravy/", note: "Taste of Home"),
        RecipeTestSite(url: "https://www.food.com/recipe/king-arthurs-sandwich-bread-361337", note: "Food.com"),
        RecipeTestSite(url: "https://www.kingarthurbaking.com/recipes/king-arthurs-classic-white-sandwich-bread-recipe", note: "King Arthur, weights in grams"),
        RecipeTestSite(url: "https://www.saveur.com/recipes/ultimate-chocolate-chip-cookie/", note: "Saveur"),
        RecipeTestSite(url: "https://sunset.com/recipe/braised-spiced-short-ribs", note: "Sunset, older site"),
        RecipeTestSite(url: "https://www.bbcgoodfoodme.com/recipes/the-best-spaghetti-bolognese", note: "BBC Good Food ME, metric"),

        // Paywalled
        RecipeTestSite(url: "https://cooking.nytimes.com/recipes/12861-orecchiette-with-cherry-tomatoes-and-arugula", note: "NYT Cooking, paywalled"),
        RecipeTestSite(url: "https://www.americastestkitchen.com/recipes/437-orecchiette-with-broccoli-sausage-and-roasted-peppers", note: "America's Test Kitchen, paywalled"),

        // Food blogs
        RecipeTestSite(url: "https://www.budgetbytes.com/one-pot-veggie-pasta/", note: "Budget Bytes"),
        RecipeTestSite(url: "https://www.budgetbytes.com/italian-wonderpot/", note: "Budget Bytes"),
        RecipeTestSite(url: "https://www.budgetbytes.com/one-pot-sausage-mushroom-pasta/", note: "Budget Bytes"),
        RecipeTestSite(url: "https://www.recipetineats.com/chicken-enchiladas/", note: "RecipeTin Eats, sectioned ingredients"),
        RecipeTestSite(url: "https://www.recipetineats.com/wprm_print/butter-chicken", note: "RecipeTin Eats, print view"),
        RecipeTestSite(url: "https://loveandlemons.com/vegetarian-chili-recipe", note: "Love and Lemons, redirects to www"),
        RecipeTestSite(url: "https://www.loveandlemons.com/banana-bread/", note: "Love and Lemons"),
        RecipeTestSite(url: "https://cookieandkate.com/vegetarian-chili-recipe/", note: "Cookie and Kate"),
        RecipeTestSite(url: "https://www.onceuponachef.com/recipes/banana-bread.html", note: "Once Upon a Chef"),
        RecipeTestSite(url: "https://www.onceuponachef.com/recipes/red-wine-braised-short-ribs.html", note: "Once Upon a Chef"),
        RecipeTestSite(url: "https://preppykitchen.com/chicken-enchiladas", note: "Preppy Kitchen"),
        RecipeTestSite(url: "https://www.acouplecooks.com/chicken-enchiladas-recipe/", note: "A Couple Cooks"),
        RecipeTestSite(url: "https://easychickenrecipes.com/creamy-white-chicken-enchiladas/", note: "Easy Chicken Recipes"),
        RecipeTestSite(url: "https://www.eatingonadime.com/banana-bread-recipe/", note: "Eating on a Dime"),
        RecipeTestSite(url: "https://www.alisoneroman.com/recipes/tangy-braised-short-ribs", note: "Alison Roman, Squarespace site"),

        // Recipes inside ordinary web pages
        RecipeTestSite(url: "https://www.cbsnews.com/news/recipe-orecchiette-con-le-cime-di-rapa-by-elizabeth-minchilli", note: "News article with a recipe in the text"),
        RecipeTestSite(url: "https://www.tn.gov/wfhtn/resources/recipes/soups/homemade-vegetarian-chili.html", note: "Government page, plain HTML"),

        // Shared links
        RecipeTestSite(
            url: "https://l.facebook.com/l.php?u=https%3A%2F%2Fwww.budgetbytes.com%2Fone-pot-roasted-red-pepper-pasta%2F&h=AT0test&fbclid=IwAR0test",
            note: "Facebook-wrapped link"
        ),

        // Pages with no recipe: these should fail cleanly
        RecipeTestSite(url: "https://www.recipetineats.com/", note: "Home page, no recipe", expectsRecipe: false),
    ]
}

/// What one site produced. Plain values only, so it can come back from a concurrent task.
struct SiteResult: Sendable {
    let site: RecipeTestSite
    var fetchError: String?
    var title = ""
    var source = ""
    var ingredientCount = 0
    var stepCount = 0
    var totalMinutes: Int?
    /// Things that put something wrong on the grocery list.
    var problems: [String] = []
    /// Things that are worth knowing but don't break the list.
    var warnings: [String] = []

    var status: String {
        if fetchError != nil { return "❌ FAILED" }
        if !problems.isEmpty { return "⚠️ ISSUES" }
        return "✅ OK"
    }
}

final class RecipeSiteTests: XCTestCase {

    func testRecipeSites() async throws {
        let sites = RecipeSiteCorpus.sites

        // Fetch all sites at once; each request is to a different server.
        let results: [SiteResult] = await withTaskGroup(of: (Int, SiteResult).self) { group in
            for (index, site) in sites.enumerated() {
                group.addTask { (index, await RecipeSiteTests.check(site)) }
            }
            var ordered = [SiteResult?](repeating: nil, count: sites.count)
            for await (index, result) in group {
                ordered[index] = result
            }
            return ordered.compactMap { $0 }
        }

        for result in results {
            if let error = result.fetchError {
                XCTFail("\(result.site.note): \(error) — \(result.site.url)")
            } else if !result.problems.isEmpty {
                let sample = result.problems.prefix(3).joined(separator: "; ")
                XCTFail("\(result.site.note): \(result.problems.count) ingredient problem(s), e.g. \(sample) — \(result.site.url)")
            }
        }

        attachReport(Self.report(results), named: "Recipe site report")
    }

    // MARK: - Checking one site

    static func check(_ site: RecipeTestSite) async -> SiteResult {
        var result = SiteResult(site: site)
        let url = RecipeFetcher.unwrapRedirect(site.url)

        let fetched: RecipeFetchResult
        do {
            fetched = try await RecipeFetcher.fetch(from: url)
        } catch {
            if site.expectsRecipe {
                result.fetchError = await describe(error, url: url)
            }
            return result
        }

        if !site.expectsRecipe {
            result.problems.append("Found a recipe (\"\(fetched.title)\") on a page that shouldn't have one")
        }

        let steps = RecipeFetcher.extractSteps(from: fetched.steps)
        result.title = fetched.title
        result.source = fetched.source.rawValue
        result.ingredientCount = fetched.ingredients.count
        result.stepCount = steps.count
        result.totalMinutes = fetched.totalMinutes

        if fetched.title == "Untitled Recipe" { result.warnings.append("No title found") }
        if IngredientChecks.hasHTML(fetched.title) { result.warnings.append("HTML left in the title: \(fetched.title)") }
        if fetched.ingredients.count < 3 { result.warnings.append("Only \(fetched.ingredients.count) ingredient(s) found") }
        if steps.isEmpty { result.warnings.append("No steps found") }
        if steps.contains(where: IngredientChecks.hasHTML) { result.warnings.append("HTML left in the steps") }
        if fetched.totalMinutes == nil { result.warnings.append("No cooking time on the page (the app will estimate one)") }

        let parsed = IngredientCategorizer.categorizeWithKeywords(fetched.ingredients)
        for (raw, item) in zip(fetched.ingredients, parsed) {
            if let issue = IngredientChecks.issue(raw: raw, name: item.name, quantity: item.quantity) {
                result.problems.append("\"\(raw)\" → \(issue)")
            }
        }
        return result
    }

    /// Turns a fetch error into something useful, adding the HTTP status when the site refused the request.
    static func describe(_ error: Error, url: String) async -> String {
        var message = error.localizedDescription
        if let target = URL(string: url),
           let reply = try? await URLSession.shared.data(from: target),
           let http = reply.1 as? HTTPURLResponse,
           http.statusCode != 200 {
            message += " (HTTP \(http.statusCode))"
        }
        return message
    }

    // MARK: - Report

    static func report(_ results: [SiteResult]) -> String {
        let ok = results.filter { $0.fetchError == nil && $0.problems.isEmpty }.count
        let failed = results.filter { $0.fetchError != nil }.count
        let issues = results.count - ok - failed

        var lines = [
            "Recipe sites: \(ok) OK, \(issues) with ingredient issues, \(failed) failed, out of \(results.count)",
            "",
        ]
        for result in results {
            var summary = "\(result.status)  \(result.site.note)"
            if result.fetchError == nil && result.site.expectsRecipe {
                let time = result.totalMinutes.map { "\($0) min" } ?? "no time"
                summary += "  [\(result.source), \(result.ingredientCount) ingredients, \(result.stepCount) steps, \(time)]"
            }
            lines.append(summary)
            lines.append("    \(result.site.url)")
            if !result.title.isEmpty { lines.append("    Title: \(result.title)") }
            if let error = result.fetchError { lines.append("    Error: \(error)") }
            for problem in result.problems { lines.append("    ✗ \(problem)") }
            for warning in result.warnings { lines.append("    · \(warning)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
