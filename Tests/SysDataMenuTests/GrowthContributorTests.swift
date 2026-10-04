import Foundation
import Testing

@testable import SysDataMenu

/// The answer behind the growth notification: which items made a category
/// bigger than it usually is.
struct GrowthContributorTests {
    private let megabyte: Int64 = 1_048_576

    private func scan(_ day: Int, _ sizes: [String: Int64], category: String = "tools") -> ScanHistory.Scan {
        ScanHistory.Scan(
            date: Date(timeIntervalSince1970: Double(day) * 86_400),
            totalBytes: sizes.values.reduce(0, +), freeBytes: 0, sizes: sizes,
            names: Dictionary(uniqueKeysWithValues: sizes.keys.map { ($0, $0.uppercased()) }),
            categories: Dictionary(uniqueKeysWithValues: sizes.keys.map { ($0, category) })
        )
    }

    private func log(_ scans: [ScanHistory.Scan]) -> ScanHistory.Log {
        var log = ScanHistory.Log()
        log.scans = scans
        return log
    }

    @Test func theItemThatGrewIsNamedWithItsUsualSize() {
        let history = log([
            scan(1, ["cache": 500 * megabyte, "models": 2_000 * megabyte]),
            scan(2, ["cache": 520 * megabyte, "models": 2_000 * megabyte]),
            scan(3, ["cache": 480 * megabyte, "models": 2_000 * megabyte]),
            scan(4, ["cache": 3_500 * megabyte, "models": 2_000 * megabyte]),
        ])
        let result = ScanHistory.growthContributors(in: .tools, log: history)
        #expect(result.map(\.id) == ["cache"])
        #expect(result.first?.baselineBytes == 500 * megabyte)
        #expect(result.first?.growthBytes == 3_000 * megabyte)
    }

    @Test func anItemNoEarlierScanKnewIsMarkedNew() {
        let history = log([
            scan(1, ["old": 100 * megabyte]), scan(2, ["old": 100 * megabyte]),
            scan(3, ["old": 100 * megabyte, "fresh": 900 * megabyte]),
        ])
        let fresh = ScanHistory.growthContributors(in: .tools, log: history).first { $0.id == "fresh" }
        #expect(fresh?.isNew == true)
        #expect(fresh?.growthBytes == 900 * megabyte)
    }

    /// A cache that moved by a few megabytes is not a cause.
    @Test func wobbleBelowFiftyMegabytesIsLeftOut() {
        let history = log([
            scan(1, ["cache": 500 * megabyte]), scan(2, ["cache": 500 * megabyte]),
            scan(3, ["cache": 530 * megabyte]),
        ])
        #expect(ScanHistory.growthContributors(in: .tools, log: history).isEmpty)
    }

    @Test func onlyTheNamedCategoryIsConsidered() {
        let history = log([
            scan(1, ["a": 100 * megabyte]), scan(2, ["a": 100 * megabyte]),
            scan(3, ["a": 1_000 * megabyte]),
        ])
        #expect(ScanHistory.growthContributors(in: .docker, log: history).isEmpty)
    }

    @Test func withNothingToCompareAgainstThereIsNoAnswer() {
        #expect(ScanHistory.growthContributors(in: .tools, log: log([scan(1, ["a": 900 * megabyte])])).isEmpty)
        #expect(ScanHistory.growthContributors(in: .tools, log: ScanHistory.Log()).isEmpty)
    }
}
