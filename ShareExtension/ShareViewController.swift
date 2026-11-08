//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Justin Biggs on 4/26/26.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    // IMPORTANT: This must match the App Group configured in both targets
    private let appGroupID = "group.com.mindframe.ListToShop"
    private let sharedKey = "SharedRecipeURL"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedURL()
    }

    private func handleSharedURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                        DispatchQueue.main.async {
                            if let url = item as? URL {
                                self?.saveAndOpen(url.absoluteString)
                            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                self?.saveAndOpen(url.absoluteString)
                            } else {
                                self?.close()
                            }
                        }
                    }
                    return
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                        DispatchQueue.main.async {
                            if let text = item as? String, text.hasPrefix("http") {
                                self?.saveAndOpen(text)
                            } else {
                                self?.close()
                            }
                        }
                    }
                    return
                }
            }
        }

        close()
    }

    private func saveAndOpen(_ recipeURL: String) {
        // Save the URL to shared UserDefaults via App Group
        if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
            sharedDefaults.set(recipeURL, forKey: sharedKey)
            sharedDefaults.synchronize()
        }

        // Open the main app via custom URL scheme
        guard let encoded = recipeURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "listtoshop://add?url=\(encoded)") else {
            close()
            return
        }

        extensionContext?.open(appURL) { [weak self] _ in
            self?.close()
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
