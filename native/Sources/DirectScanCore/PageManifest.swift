import Foundation

public enum PageSide: String, Codable { case front, back }
public enum JobEndReason: String, Codable { case completed, stop, idleTimeout, interrupted }
public struct ValidatedPage: Codable, Equatable {
    public let index: Int
    public let sheet: Int
    public let side: PageSide
    public let sourceName: String
    public let width: Int
    public let height: Int
}
public struct PageManifest: Codable {
    public var pages: [ValidatedPage] = []
    public var endReason: JobEndReason?
    public var duplex: Bool
    public var hasIncompleteSheet: Bool {
        duplex && Dictionary(grouping: pages, by: \.sheet).values.contains { Set($0.map(\.side)).count != 2 }
    }
    public init(duplex: Bool) { self.duplex = duplex }
    mutating func append(_ page: ValidatedPage) throws {
        guard endReason == nil, page.index == pages.count + 1, page.sheet > 0,
              !pages.contains(where: { $0.sourceName == page.sourceName || ($0.sheet == page.sheet && $0.side == page.side) }),
              duplex || page.side == .front else { throw ScanFailure.invalidSource }
        let expectedSheet = duplex ? (pages.count / 2 + 1) : pages.count + 1
        let expectedSide: PageSide = duplex && pages.count % 2 == 1 ? .back : .front
        guard page.sheet == expectedSheet, page.side == expectedSide else { throw ScanFailure.incompletePair }
        pages.append(page)
    }
}
