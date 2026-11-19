//
//  EmojiCatalog.swift
//  IGram
//

import Foundation

/// Emoji grouped into tdesktop's sections, built from Unicode properties so
/// the list follows the system's emoji support.
nonisolated enum EmojiCatalog {
    struct Section: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let emoji: [String]
    }

    static let sections: [Section] = {
        var used = Set<String>()
        func collect(_ ranges: [ClosedRange<UInt32>]) -> [String] {
            ranges.flatMap { range in
                range.compactMap { value -> String? in
                    guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                          !(0x1F1E6...0x1F1FF).contains(value), !(0x1F3FB...0x1F3FF).contains(value)
                    else { return nil }
                    let emoji = String(Character(scalar))
                    return used.insert(emoji).inserted ? emoji : nil
                }
            }
        }
        let people = collect([0x1F600...0x1F64F, 0x1F90C...0x1F92F, 0x1F970...0x1F97A, 0x1F9D0...0x1F9DF, 0x1F440...0x1F4AB, 0x1F574...0x1F57A, 0x1F590...0x1F596, 0x1FAE0...0x1FAF8])
        let nature = collect([0x1F400...0x1F43F, 0x1F980...0x1F9AE, 0x1F330...0x1F344, 0x1F308...0x1F30C, 0x1F31A...0x1F320, 0x1FAB0...0x1FABF])
        let food = collect([0x1F345...0x1F37F, 0x1F950...0x1F96F, 0x1F9C0...0x1F9CB, 0x1FAD0...0x1FADF])
        let activity = collect([0x1F380...0x1F3CF, 0x1F93C...0x1F94F, 0x1F9E9...0x1F9F0, 0x26BD...0x26BE])
        let travel = collect([0x1F680...0x1F6FF, 0x1F3D4...0x1F3F7, 0x1F300...0x1F307, 0x1F30D...0x1F319])
        let objects = collect([0x1F4AC...0x1F53D, 0x1F9F1...0x1F9FF, 0x1FA70...0x1FAAF, 0x231A...0x23FF])
        let featured = ["❤️", "✨", "⭐️", "✅", "❌"]
        let symbols = featured + collect([0x1F300...0x1FAFF, 0x2600...0x27BF]).filter { !featured.contains($0) }
        let flags = Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .sorted()
            .compactMap(flag)
        return [
            Section(id: "people", title: String(localized: "Smileys & People"), systemImage: "face.smiling", emoji: people),
            Section(id: "nature", title: String(localized: "Animals & Nature"), systemImage: "leaf", emoji: nature),
            Section(id: "food", title: String(localized: "Food & Drink"), systemImage: "fork.knife", emoji: food),
            Section(id: "activity", title: String(localized: "Activity"), systemImage: "soccerball", emoji: activity),
            Section(id: "travel", title: String(localized: "Travel & Places"), systemImage: "car", emoji: travel),
            Section(id: "objects", title: String(localized: "Objects"), systemImage: "lightbulb", emoji: objects),
            Section(id: "symbols", title: String(localized: "Symbols"), systemImage: "heart", emoji: symbols),
            Section(id: "flags", title: String(localized: "Flags"), systemImage: "flag", emoji: flags),
        ]
    }()

    /// Regional indicator pair for an ISO country code, e.g. "US" → 🇺🇸.
    static func flag(_ code: String) -> String? {
        var result = ""
        for letter in code.uppercased().unicodeScalars {
            guard (65...90).contains(letter.value), let indicator = Unicode.Scalar(0x1F1E6 - 65 + letter.value) else { return nil }
            result.unicodeScalars.append(indicator)
        }
        return result
    }

    // MARK: - Recents

    private static let recentsKey = "emoji.recent"
    static let recentLimit = 32

    static var recent: [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? ["😂", "❤️", "👍", "😍", "🔥", "🙏", "😭", "🥰"]
    }

    static func noteUsed(_ emoji: String) {
        var list = recent.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        UserDefaults.standard.set(Array(list.prefix(recentLimit)), forKey: recentsKey)
    }
}
