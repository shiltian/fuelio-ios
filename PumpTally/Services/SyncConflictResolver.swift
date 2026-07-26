import Foundation

/// Pure last-writer-wins decision logic shared by initial and incremental sync.
enum SyncConflictResolver {
    enum Winner: Equatable {
        case cloud
        case local
        case tie
    }

    /// Resolve legacy records safely by falling back from `modifiedAt` to
    /// `createdAt`. Equal effective timestamps deliberately make no change.
    nonisolated static func resolve(
        cloudModifiedAt: Date?,
        cloudCreatedAt: Date?,
        localModifiedAt: Date?,
        localCreatedAt: Date?
    ) -> Winner {
        let cloudDate = cloudModifiedAt ?? cloudCreatedAt ?? .distantPast
        let localDate = localModifiedAt ?? localCreatedAt ?? .distantPast

        if cloudDate > localDate { return .cloud }
        if localDate > cloudDate { return .local }
        return .tie
    }
}
