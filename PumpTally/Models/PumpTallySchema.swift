import Foundation
import SwiftData

// MARK: - Schema V1 (original schema, no modifiedAt)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Vehicle.self, FuelingRecord.self]
    }

    @Model
    final class Vehicle {
        var id: UUID = UUID()
        var name: String = ""
        var make: String?
        var model: String?
        var year: Int?
        var createdAt: Date = Date()
        var unitSystemRaw: String = "imperial"

        @Relationship(deleteRule: .cascade, inverse: \FuelingRecord.vehicle)
        var fuelingRecords: [FuelingRecord]?

        var cachedTotalSpent: Double?
        var cachedTotalDistance: Double?
        var cachedTotalFuel: Double?
        var cachedAverageEfficiency: Double?
        var cachedAverageCostPerDistance: Double?
        var cachedAverageFillUpCost: Double?
        var cachedAveragePricePerFuelUnit: Double?
        var cachedBestEfficiency: Double?
        var cachedWorstEfficiency: Double?
        var cachedHighestPricePerFuelUnit: Double?
        var cachedLowestPricePerFuelUnit: Double?
        var cachedRecordCount: Int?
        var cacheLastUpdated: Date?

        init(name: String = "") {
            self.name = name
        }
    }

    @Model
    final class FuelingRecord {
        var id: UUID = UUID()
        var date: Date = Date()
        var odometer: Double = 0
        var pricePerFuelUnit: Double = 0
        var fuelAmount: Double = 0
        var totalCost: Double = 0
        var fillUpTypeRaw: String = "full"
        var notes: String?
        var createdAt: Date = Date()
        var vehicle: Vehicle

        var cachedPreviousOdometer: Double?
        var cachedDistanceDriven: Double?
        var cachedEfficiency: Double?
        var cachedCostPerDistance: Double?

        init(vehicle: Vehicle) {
            self.vehicle = vehicle
        }
    }
}

// MARK: - Schema V2 (adds modifiedAt: Date?)
// References the top-level Vehicle and FuelingRecord classes directly so that
// SwiftData instantiates the same types the rest of the app uses at runtime.

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [PumpTally.Vehicle.self, PumpTally.FuelingRecord.self]
    }
}

// MARK: - Migration Plan

enum PumpTallyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}
