//
//  Logging.swift
//  IGram
//

import OSLog

/// Unified logging categories, mirroring the log areas tdesktop writes to `log.txt`.
nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "IGram"

    static let tdlib = Logger(subsystem: subsystem, category: "tdlib")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
