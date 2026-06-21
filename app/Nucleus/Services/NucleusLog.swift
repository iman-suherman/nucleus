import OSLog

enum NucleusLog {
    static let app = Logger(subsystem: "net.suherman.nucleus", category: "app")
    static let ai = Logger(subsystem: "net.suherman.nucleus", category: "ai")
    static let music = Logger(subsystem: "net.suherman.nucleus", category: "music")
}
