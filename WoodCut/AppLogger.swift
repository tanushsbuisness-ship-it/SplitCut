import OSLog

enum AppLogger {
    static let app = Logger(subsystem: "TS.WoodCut", category: "app")
    static let auth = Logger(subsystem: "TS.WoodCut", category: "auth")
    static let sync = Logger(subsystem: "TS.WoodCut", category: "sync")
    static let monetization = Logger(subsystem: "TS.WoodCut", category: "monetization")
    static let optimizer = Logger(subsystem: "TS.WoodCut", category: "optimizer")
    static let scrap = Logger(subsystem: "TS.WoodCut", category: "scrap")
    static let export = Logger(subsystem: "TS.WoodCut", category: "export")
    static let ui = Logger(subsystem: "TS.WoodCut", category: "ui")
}
