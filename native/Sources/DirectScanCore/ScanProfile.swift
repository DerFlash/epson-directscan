import Foundation
import CoreGraphics

public enum OrientationMode: String, Codable, CaseIterable { case fixed, vision, epson }

public struct ScanArea: Codable, Equatable {
    public var widthMM: Double?
    public var heightMM: Double?
    public init(widthMM: Double? = nil, heightMM: Double? = nil) { self.widthMM = widthMM; self.heightMM = heightMM }
    public var isAutomatic: Bool { widthMM == nil && heightMM == nil }
    public func validate() throws {
        guard heightMM == nil || widthMM != nil,
              widthMM.map({ $0.isFinite && (50.8...215.9).contains($0) }) ?? true,
              heightMM.map({ $0.isFinite && (50.8...297).contains($0) }) ?? true else { throw ScanFailure.invalidSettings }
    }
    public func rectangle(maximumMM: CGSize) throws -> CGRect {
        try validate()
        guard maximumMM.width.isFinite, maximumMM.height.isFinite, maximumMM.width > 0, maximumMM.height > 0 else { throw ScanFailure.unsupportedProfile }
        if isAutomatic { return CGRect(origin:.zero,size:maximumMM) }
        guard let w = widthMM, let h = heightMM, w <= maximumMM.width, h <= maximumMM.height else { throw ScanFailure.unsupportedProfile }
        return CGRect(x:(maximumMM.width-w)/2,y:0,width:w,height:h)
    }
}

/// A hardware-accepted relationship; never manufactured from OCR guesses.
public struct DuplexMapping: Codable, Equatable {
    public var sign: Int
    public var offset: Int
    public init(sign: Int, offset: Int) { self.sign = sign; self.offset = offset }
    public var isValid: Bool { [-1,1].contains(sign) && [0,90,180,270].contains(offset) }
    public func back(for front: Int, printedOffset: Int = 0) -> Int { ((sign*front+offset+printedOffset)%360+360)%360 }
}

public struct ScanProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var area = ScanArea()
    public var orientation: OrientationMode = .fixed
    public var frontRotation = 0
    public var backRotation = 0
    public var printedBackOffset = 0
    // Missing legacy/explicitly uncalibrated values retain conservative fallback.
    public var icaMapping: DuplexMapping?
    public var feedingMapping: DuplexMapping?
    public init(id: UUID = UUID(), name: String) {
        self.id = id; self.name = name
        // Both paths physically measured on ES-C320W/driver6.7.84. Native
        // helpers already reject other USB products and driver revisions.
        icaMapping=DuplexMapping(sign:-1,offset:0)
        feedingMapping=DuplexMapping(sign:-1,offset:0)
    }
    public func validate() throws {
        try area.validate()
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.count <= 60,
              [frontRotation,backRotation,printedBackOffset].allSatisfy({ [0,90,180,270].contains($0) }),
              icaMapping?.isValid ?? true, feedingMapping?.isValid ?? true else { throw ScanFailure.invalidSettings }
    }
    /// Historical profiles remain decodable. Enforce new operational limits at
    /// capture/processing boundaries, without hiding old settings or originals.
    public func validateForCapture() throws {
        try validate()
        guard area.isAutomatic || orientation != .epson else {throw ScanFailure.unsupportedProfile}
    }
}
