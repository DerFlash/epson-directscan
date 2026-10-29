import Foundation

public struct OrientationEvidence {
    public let rotation: Int
    public let score: Double
    public let lines: Int
    public init(rotation: Int, score: Double, lines: Int) { self.rotation = rotation; self.score = score; self.lines = lines }
}
public enum OrientationNotice: String, Codable { case uncertain, uncalibrated, conflict, unavailable, missingPair }
public struct OrientationResult {
    public let front: Int
    public let back: Int?
    public let notice: OrientationNotice?
}
public enum OrientationDecision {
    private static func valid(_ e: [OrientationEvidence]) -> Bool {
        e.count == 4 && Set(e.map(\.rotation)) == Set([0,90,180,270]) && e.allSatisfy { $0.score.isFinite && $0.score >= 0 && $0.lines >= 0 }
    }
    private static func winner(_ e: [OrientationEvidence]) -> Int? {
        guard valid(e) else { return nil }
        let sorted = e.sorted { $0.score > $1.score }, a = sorted[0], b = sorted[1]
        guard a.score >= 12, a.lines >= 2, (a.score-b.score)/a.score >= 0.20 else { return nil }
        return a.rotation
    }
    public static func confidentRotation(_ evidence:[OrientationEvidence])->Int? {winner(evidence)}
    public static func resolve(front: [OrientationEvidence], back: [OrientationEvidence]?, mapping: DuplexMapping?,
                               fallbackFront: Int, fallbackBack: Int, printedOffset: Int = 0) -> OrientationResult {
        func fallback(_ reason: OrientationNotice) -> OrientationResult {
            OrientationResult(front:fallbackFront,back:back == nil ? nil : fallbackBack,notice:reason)
        }
        guard valid(front), back.map(valid) ?? true else { return fallback(.unavailable) }
        guard let back else {
            guard let angle = winner(front) else { return fallback(.uncertain) }
            return OrientationResult(front:angle,back:nil,notice:nil)
        }
        guard let mapping, mapping.isValid else { return fallback(.uncalibrated) }
        if let a = winner(front), let b = winner(back), mapping.back(for:a,printedOffset:printedOffset) != b { return fallback(.conflict) }
        let combined = front.map { a -> OrientationEvidence in
            let b = back.first { $0.rotation == mapping.back(for:a.rotation,printedOffset:printedOffset) }!
            return OrientationEvidence(rotation:a.rotation,score:a.score+b.score,lines:a.lines+b.lines)
        }
        guard let angle = winner(combined) else { return fallback(.uncertain) }
        return OrientationResult(front:angle,back:mapping.back(for:angle,printedOffset:printedOffset),notice:nil)
    }
}
