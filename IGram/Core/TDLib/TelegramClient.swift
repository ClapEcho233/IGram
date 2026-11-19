//
//  TelegramClient.swift
//  IGram
//

import Foundation
import OSLog
@preconcurrency import TDLibKit

/// TDLib reports failures with its own `Error` struct, which shadows `Swift.Error`
/// once TDLibKit is imported. Use this alias to keep call sites unambiguous.
typealias TDError = TDLibKit.Error

/// Bridges one TDLib JSON client instance to Swift concurrency.
///
/// tdesktop speaks MTProto directly through its `mtproto` module. The Swift
/// rewrite delegates the protocol, local database and update sequencing to
/// TDLib and consumes its ordered update stream instead.
nonisolated final class TelegramClient: @unchecked Sendable {
    /// `td_receive` may only be polled from one thread per process, so all
    /// clients share a single manager.
    nonisolated(unsafe) private static let manager = TDLibClientManager()

    /// The typed TDLib API. Calls are thread-safe and may be awaited from any actor.
    let api: TDLibClient

    /// Every update TDLib emits for this client, in order. The stream finishes
    /// after `authorizationStateClosed`; a new client is required afterwards.
    let updates: AsyncStream<Update>

    init(logVerbosity: Int = 1) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Update.self,
            bufferingPolicy: .unbounded
        )
        updates = stream
        api = Self.manager.createClient { data, client in
            let update: Update
            do {
                update = try client.decoder.decode(Update.self, from: data)
            } catch {
                Log.tdlib.error("Dropped undecodable update: \(error.localizedDescription, privacy: .public)")
                return
            }
            continuation.yield(update)
            if case .updateAuthorizationState(let value) = update,
               case .authorizationStateClosed = value.authorizationState {
                continuation.finish()
            }
        }
        _ = try? api.execute(query: DTO(SetLogVerbosityLevel(newVerbosityLevel: logVerbosity)))
    }
}

extension TDError {
    /// TDLib error messages are upper-snake identifiers such as `PHONE_CODE_INVALID`.
    /// Turn the common ones into readable text for alerts.
    nonisolated var displayMessage: String {
        switch message {
        case "PHONE_NUMBER_INVALID": return String(localized: "Invalid phone number. Please try again.")
        case "PHONE_CODE_INVALID": return String(localized: "Invalid code. Please try again.")
        case "PHONE_CODE_EXPIRED": return String(localized: "The code has expired. Request a new one.")
        case "PASSWORD_HASH_INVALID": return String(localized: "Invalid password. Please try again.")
        case "PHONE_NUMBER_BANNED": return String(localized: "This phone number is banned.")
        case "FIRSTNAME_INVALID": return String(localized: "Invalid first name. Please try again.")
        case "API_ID_INVALID", "API_ID_PUBLISHED_FLOOD":
            return String(localized: "The API ID or hash was rejected by Telegram.")
        default:
            if message.hasPrefix("FLOOD_WAIT_"), let seconds = Int(message.dropFirst("FLOOD_WAIT_".count)) {
                let wait = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
                return String(localized: "Too many attempts. Try again in \(wait).")
            }
            return message.isEmpty ? String(localized: "Unknown error (\(code)).") : message
        }
    }
}

extension Swift.Error {
    /// A human-readable description that unwraps TDLib errors.
    nonisolated var telegramMessage: String {
        (self as? TDError)?.displayMessage ?? localizedDescription
    }
}
