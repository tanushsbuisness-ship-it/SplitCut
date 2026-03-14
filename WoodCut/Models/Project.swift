import Foundation
import SwiftData

enum ScrapUsageMode: String, CaseIterable, Codable {
    case useFirst = "Use Scrap First"
    case onlyScrap = "Only Use Scrap"
    case ignoreScrap = "Do Not Use Scrap"
}

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var kerfWidth: Double = 0.125   // inches, e.g. 0.125 for 1/8"
    var trimMargin: Double = 0.0  // inches to trim off each edge before packing
    var scrapUsageModeRaw: String = ScrapUsageMode.useFirst.rawValue

    @Relationship(deleteRule: .cascade, inverse: \MaterialItem.project)
    var materials: [MaterialItem] = []

    @Relationship(deleteRule: .cascade, inverse: \RequiredPiece.project)
    var pieces: [RequiredPiece] = []

    init(name: String, kerfWidth: Double = 0.125, trimMargin: Double = 0.0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.kerfWidth = kerfWidth
        self.trimMargin = trimMargin
        self.scrapUsageModeRaw = ScrapUsageMode.useFirst.rawValue
    }

    var scrapUsageMode: ScrapUsageMode {
        get { ScrapUsageMode(rawValue: scrapUsageModeRaw) ?? .useFirst }
        set { scrapUsageModeRaw = newValue.rawValue }
    }
}
