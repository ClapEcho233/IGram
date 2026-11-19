//
//  TDLibEnvironment.swift
//  IGram
//

import Foundation

/// Device and storage information passed to `setTdlibParameters`.
///
/// This plays the role of tdesktop's `tdata` folder handling and the device
/// description it reports in active sessions.
nonisolated struct TDLibEnvironment: Sendable {
    var databaseDirectory: URL
    var filesDirectory: URL
    var deviceModel: String
    var systemVersion: String
    var applicationVersion: String
    var systemLanguageCode: String

    /// The environment for the current process, creating storage folders on demand.
    static func current(fileManager: FileManager = .default) throws -> TDLibEnvironment {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appending(path: "IGram/tdlib", directoryHint: .isDirectory)
        let database = root.appending(path: "db", directoryHint: .isDirectory)
        let files = root.appending(path: "files", directoryHint: .isDirectory)
        for directory in [database, files] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let os = ProcessInfo.processInfo.operatingSystemVersion

        return TDLibEnvironment(
            databaseDirectory: database,
            filesDirectory: files,
            deviceModel: hardwareModel() ?? "Mac",
            systemVersion: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            applicationVersion: "\(version) (\(build))",
            systemLanguageCode: Locale.current.language.languageCode?.identifier ?? "en"
        )
    }

    /// The hardware model identifier, for example `Mac16,1`.
    static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
