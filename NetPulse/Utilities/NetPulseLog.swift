import Foundation
import os

/// 统一日志：Release 降噪，避免滥 print
enum NetPulseLog {
    private static let logger = Logger(subsystem: "com.netpulse.app", category: "app")

    static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
