import XCTest
@testable import PumpTally

final class HistoryRecordsQueryTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(
        idSuffix: Int,
        day: Int,
        cost: Double,
        odometer: Double,
        notes: String? = nil
    ) -> HistoryRecordSnapshot {
        HistoryRecordSnapshot(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", idSuffix))!,
            date: baseDate.addingTimeInterval(Double(day) * 86_400),
            totalCost: cost,
            odometer: odometer,
            notes: notes
        )
    }

    func testSearchMatchesNotesCostAndOdometer() {
        let notes = snapshot(idSuffix: 1, day: 1, cost: 20, odometer: 1_000, notes: "Road Trip")
        let cost = snapshot(idSuffix: 2, day: 2, cost: 12.50, odometer: 2_000)
        let odometer = snapshot(idSuffix: 3, day: 3, cost: 30, odometer: 12_345)
        let records = [notes, cost, odometer]

        XCTAssertEqual(
            HistoryRecordsQuery.recordIDs(
                from: records,
                searchText: "ROAD",
                sortOrder: .dateDescending
            ),
            [notes.id]
        )
        XCTAssertEqual(
            HistoryRecordsQuery.recordIDs(
                from: records,
                searchText: "12.50",
                sortOrder: .dateDescending
            ),
            [cost.id]
        )
        XCTAssertEqual(
            HistoryRecordsQuery.recordIDs(
                from: records,
                searchText: "12345",
                sortOrder: .dateDescending
            ),
            [odometer.id]
        )
    }

    func testEverySortOrder() {
        let oldestExpensive = snapshot(idSuffix: 1, day: 1, cost: 80, odometer: 1_000)
        let middleCheap = snapshot(idSuffix: 2, day: 2, cost: 20, odometer: 2_000)
        let newestMedium = snapshot(idSuffix: 3, day: 3, cost: 50, odometer: 3_000)
        let records = [middleCheap, newestMedium, oldestExpensive]

        XCTAssertEqual(
            HistoryRecordsQuery.recordIDs(from: records, searchText: "", sortOrder: .dateDescending),
            [newestMedium.id, middleCheap.id, oldestExpensive.id]
        )
        XCTAssertEqual(
            HistoryRecordsQuery.recordIDs(from: records, searchText: "", sortOrder: .dateAscending),
            [oldestExpensive.id, middleCheap.id, newestMedium.id]
        )
        XCTAssertEqual(
            HistoryRecordsQuery.recordIDs(from: records, searchText: "", sortOrder: .costHighest),
            [oldestExpensive.id, newestMedium.id, middleCheap.id]
        )
        XCTAssertEqual(
            HistoryRecordsQuery.recordIDs(from: records, searchText: "", sortOrder: .costLowest),
            [middleCheap.id, newestMedium.id, oldestExpensive.id]
        )
    }

    func testEqualValuesHaveStableOrdering() {
        let largerID = snapshot(idSuffix: 2, day: 1, cost: 20, odometer: 1_000)
        let smallerID = snapshot(idSuffix: 1, day: 1, cost: 20, odometer: 2_000)

        for sortOrder in HistorySortOrder.allCases {
            XCTAssertEqual(
                HistoryRecordsQuery.recordIDs(
                    from: [largerID, smallerID],
                    searchText: "",
                    sortOrder: sortOrder
                ),
                [smallerID.id, largerID.id]
            )
        }
    }
}
