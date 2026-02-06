import Foundation
import CloudKit

/// Manages iCloud sync state and preferences using UserDefaults/AppStorage
final class SyncStateManager: ObservableObject {

    // MARK: - Published State

    @Published var iCloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled)
        }
    }

    @Published var initialSyncCompleted: Bool {
        didSet {
            UserDefaults.standard.set(initialSyncCompleted, forKey: Keys.initialSyncCompleted)
        }
    }

    @Published var syncStatus: SyncStatus = .idle

    // MARK: - Sync Status Enum

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case synced
        case error(String)
        case unavailable

        var displayText: String {
            switch self {
            case .idle: return "Not Syncing"
            case .syncing: return "Syncing..."
            case .synced: return "Synced"
            case .error(let msg): return "Error: \(msg)"
            case .unavailable: return "iCloud Unavailable"
            }
        }

        var isInProgress: Bool {
            if case .syncing = self { return true }
            return false
        }
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let initialSyncCompleted = "initialSyncCompleted"
        static let serverChangeToken = "serverChangeToken"
    }

    // MARK: - Initialization

    init() {
        self.iCloudSyncEnabled = UserDefaults.standard.bool(forKey: Keys.iCloudSyncEnabled)
        self.initialSyncCompleted = UserDefaults.standard.bool(forKey: Keys.initialSyncCompleted)
    }

    // MARK: - Server Change Token

    /// The last known server change token for incremental sync
    var serverChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.serverChangeToken) else {
                return nil
            }
            do {
                return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
            } catch {
                print("Failed to decode server change token: \(error)")
                return nil
            }
        }
        set {
            if let token = newValue {
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                    UserDefaults.standard.set(data, forKey: Keys.serverChangeToken)
                } catch {
                    print("Failed to encode server change token: \(error)")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.serverChangeToken)
            }
        }
    }

    // MARK: - State Management

    /// Reset all sync state (when disabling sync)
    func resetSyncState() {
        initialSyncCompleted = false
        serverChangeToken = nil
        syncStatus = .idle
    }

    /// Mark sync as enabled and initial sync complete
    func markInitialSyncComplete() {
        initialSyncCompleted = true
        syncStatus = .synced
    }
}
