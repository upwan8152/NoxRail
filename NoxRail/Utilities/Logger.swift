import Foundation
import os.log

/// Structured logging for NoxRail
enum NoxLogger {
    static let ble = Logger(subsystem: "com.noxrail", category: "BLE")
    static let mesh = Logger(subsystem: "com.noxrail", category: "Mesh")
    static let encryption = Logger(subsystem: "com.noxrail", category: "Encryption")
    static let persistence = Logger(subsystem: "com.noxrail", category: "Persistence")
    static let ui = Logger(subsystem: "com.noxrail", category: "UI")
    static let general = Logger(subsystem: "com.noxrail", category: "General")
}

// MARK: - Logger Extensions

extension Logger {
    func debug(_ message: String) {
        self.log(level: .debug, "\(message)")
    }
    
    func info(_ message: String) {
        self.log(level: .info, "\(message)")
    }
    
    func warning(_ message: String) {
        self.log(level: .error, "⚠️ \(message)")
    }
    
    func error(_ message: String) {
        self.log(level: .fault, "❌ \(message)")
    }
}
