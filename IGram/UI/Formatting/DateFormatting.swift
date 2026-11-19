//
//  DateFormatting.swift
//  IGram
//

import Foundation
@preconcurrency import TDLibKit

/// Date strings used across the chat list and history.
struct DateFormatting {
    var now: Date = .now
    var calendar: Calendar = .current
    var locale: Locale = .current

    private var timeZone: TimeZone { calendar.timeZone }

    func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
    }

    /// Chat list timestamp: time today, weekday this week, otherwise the date.
    func chatListTimestamp(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return time(date)
        }
        let startOfToday = calendar.startOfDay(for: now)
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday), date >= weekAgo, date < now {
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).weekday(.abbreviated))
        }
        return date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone))
    }

    /// Floating date separator in the history: "Today", "Yesterday", "Monday, March 3".
    func daySeparator(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        var format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.wide).day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            format = format.year()
        } else {
            format = format.weekday(.wide)
        }
        return date.formatted(format)
    }

    /// Presence line for a user, like tdesktop's `Data::OnlineText`.
    func presence(_ status: UserStatus) -> String {
        switch status {
        case .userStatusOnline:
            return String(localized: "online")
        case .userStatusOffline(let value):
            let date = Date(timeIntervalSince1970: TimeInterval(value.wasOnline))
            let seconds = now.timeIntervalSince(date)
            if seconds < 60 { return String(localized: "last seen just now") }
            if seconds < 3600 {
                let minutes = Int(seconds / 60)
                return String(localized: "last seen \(minutes) minutes ago")
            }
            if calendar.isDate(date, inSameDayAs: now) {
                return String(localized: "last seen today at \(time(date))")
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
                return String(localized: "last seen yesterday at \(time(date))")
            }
            let day = date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone))
            return String(localized: "last seen \(day)")
        case .userStatusRecently:
            return String(localized: "last seen recently")
        case .userStatusLastWeek:
            return String(localized: "last seen within a week")
        case .userStatusLastMonth:
            return String(localized: "last seen within a month")
        case .userStatusEmpty:
            return String(localized: "last seen a long time ago")
        }
    }

    static func isOnline(_ status: UserStatus) -> Bool {
        if case .userStatusOnline = status { return true }
        return false
    }
}

enum DurationFormatting {
    /// `m:ss` or `h:mm:ss`, as used for media durations.
    static func short(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
