import SwiftUI
import SwiftData
import os

@main
struct FuelioApp: App {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.tianshilei.fuelio",
        category: "App"
    )

    @State private var importedFileURL: URL?
    @State private var hasInitializedCache = false

    /// CloudKit sync service -- shared across the app via environmentObject
    @StateObject private var cloudSyncService = CloudSyncService()

    /// Check if we're running in a test environment
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV2.self)

        // Use in-memory storage for tests to avoid file system issues.
        // Explicitly disable CloudKit — we manage iCloud sync manually via CloudSyncService
        // so SwiftData must not attempt its own automatic CloudKit integration.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isRunningTests,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: FuelioMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            // Log the full error for diagnostics before crashing
            let message = "Could not create ModelContainer: \(error.localizedDescription)\nFull error: \(error)"
            logger.fault("Could not create ModelContainer: \(error)")
            fatalError(message)
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(importedFileURL: $importedFileURL)
                .environmentObject(cloudSyncService)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .task {
                    // Build/validate cache on startup (runs once)
                    if !hasInitializedCache {
                        hasInitializedCache = true
                        initializeCache()
                        initializeCloudSync()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Pull remote changes when app returns to foreground
                    pullRemoteChangesIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Initialize statistics cache on app startup
    private func initializeCache() {
        let context = sharedModelContainer.mainContext
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context)
    }

    /// Initialize CloudKit sync if enabled and iCloud is available
    private func initializeCloudSync() {
        let stateManager = cloudSyncService.stateManager

        // Detect interrupted initial sync: the user toggled sync ON but the app
        // was killed before the initial upload/download/merge finished.
        // Reset the flag so the toggle shows OFF and the user can try again.
        if stateManager.iCloudSyncEnabled && !stateManager.initialSyncCompleted {
            Self.logger.warning("Detected interrupted initial sync — resetting iCloudSyncEnabled")
            stateManager.iCloudSyncEnabled = false
            stateManager.syncStatus = .idle
            return
        }

        guard stateManager.iCloudSyncEnabled && stateManager.initialSyncCompleted else { return }

        Task {
            // Verify the user still has iCloud available before touching CloudKit
            let available = await cloudSyncService.checkiCloudAvailability()
            guard available else { return }

            // Start monitoring local saves
            cloudSyncService.startMonitoring(container: sharedModelContainer)

            // Subscribe to remote changes
            await cloudSyncService.subscribeToRemoteChanges()

            // Pull any changes that happened while the app was closed
            let context = sharedModelContainer.mainContext
            await cloudSyncService.pullRemoteChanges(to: context)
        }
    }

    /// Pull remote changes if sync is enabled and iCloud is available
    private func pullRemoteChangesIfNeeded() {
        let stateManager = cloudSyncService.stateManager
        guard stateManager.iCloudSyncEnabled && stateManager.initialSyncCompleted else { return }

        Task {
            let available = await cloudSyncService.checkiCloudAvailability()
            guard available else { return }

            let context = sharedModelContainer.mainContext
            await cloudSyncService.pullRemoteChanges(to: context)
        }
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
            Self.logger.error("Failed to copy file: \(error.localizedDescription)")
        }
    }
}
