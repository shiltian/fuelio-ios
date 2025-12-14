import SwiftUI
import SwiftData

@main
struct FillioApp: App {
    @State private var importedFileURL: URL?
    @State private var hasInitializedCache = false

    /// Check if we're running in a test environment
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vehicle.self,
            FuelingRecord.self,
        ])

        // Use in-memory storage for tests to avoid file system issues
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isRunningTests
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(importedFileURL: $importedFileURL)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .task {
                    // Build/validate cache on startup (runs once)
                    if !hasInitializedCache {
                        hasInitializedCache = true
                        initializeCache()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Initialize statistics cache on app startup
    private func initializeCache() {
        let context = sharedModelContainer.mainContext
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context)
    }

    private func handleIncomingURL(_ url: URL) {
        // Check if it's a CSV file
        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "csv" else {
            return
        }

        // Need to start accessing security-scoped resource for files from other apps
        let accessing = url.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Copy the file to a temporary location to ensure we can access it
        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)

            // Remove existing temp file if it exists
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }

            try FileManager.default.copyItem(at: url, to: tempURL)

            // Set the URL - this will trigger the sheet in ContentView
            importedFileURL = tempURL
        } catch {
            print("Failed to copy file: \(error.localizedDescription)")
        }
    }
}

