import AppKit

@MainActor
final class BrandLogoStore {
    static let shared = BrandLogoStore()

    private var cache: [String: NSImage] = [:]
    private let fileExtensions = ["png", "svg", "ico"]
    private lazy var resourceBundle: Bundle = {
        let bundleName = "AgentUsageMonitor_AgentUsageMonitor.bundle"

        if let resourcesURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent(bundleName, isDirectory: true)
           ) {
            return packagedBundle
        }

        // SwiftPM keeps resources beside the executable during local development.
        return Bundle.module
    }()

    func preload(_ names: [String]) {
        for name in names {
            _ = image(named: name)
        }
    }

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        for fileExtension in fileExtensions {
            if let image = loadImage(name: name, fileExtension: fileExtension, subdirectory: nil) {
                cache[name] = image
                return image
            }

            if let image = loadImage(name: name, fileExtension: fileExtension, subdirectory: "Logos") {
                cache[name] = image
                return image
            }
        }

        return nil
    }

    private func loadImage(name: String, fileExtension: String, subdirectory: String?) -> NSImage? {
        guard let url = resourceBundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = true
        return image
    }
}
