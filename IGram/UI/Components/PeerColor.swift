//
//  PeerColor.swift
//  IGram
//

import SwiftUI

/// The seven built-in peer accent colors used for avatars and sender names,
/// matching tdesktop's `historyPeer*` palette (red, orange, violet, green,
/// cyan, blue, pink).
enum PeerColor {
    private static let palette: [(top: Color, bottom: Color, name: Color)] = [
        (Color(red: 1.00, green: 0.52, blue: 0.45), Color(red: 0.89, green: 0.33, blue: 0.33), Color(red: 0.85, green: 0.30, blue: 0.27)),
        (Color(red: 1.00, green: 0.75, blue: 0.40), Color(red: 0.95, green: 0.53, blue: 0.24), Color(red: 0.86, green: 0.48, blue: 0.13)),
        (Color(red: 0.75, green: 0.60, blue: 1.00), Color(red: 0.56, green: 0.43, blue: 0.91), Color(red: 0.55, green: 0.39, blue: 0.87)),
        (Color(red: 0.55, green: 0.86, blue: 0.40), Color(red: 0.32, green: 0.72, blue: 0.29), Color(red: 0.25, green: 0.65, blue: 0.20)),
        (Color(red: 0.40, green: 0.85, blue: 0.90), Color(red: 0.21, green: 0.70, blue: 0.77), Color(red: 0.16, green: 0.62, blue: 0.69)),
        (Color(red: 0.36, green: 0.73, blue: 1.00), Color(red: 0.20, green: 0.53, blue: 0.92), Color(red: 0.20, green: 0.52, blue: 0.85)),
        (Color(red: 1.00, green: 0.55, blue: 0.75), Color(red: 0.86, green: 0.36, blue: 0.59), Color(red: 0.82, green: 0.30, blue: 0.56)),
    ]

    private static func entry(_ accentColorId: Int) -> (top: Color, bottom: Color, name: Color) {
        palette[((accentColorId % palette.count) + palette.count) % palette.count]
    }

    static func gradient(_ accentColorId: Int) -> LinearGradient {
        let entry = entry(accentColorId)
        return LinearGradient(colors: [entry.top, entry.bottom], startPoint: .top, endPoint: .bottom)
    }

    /// Sender name color in group chats.
    static func name(_ accentColorId: Int) -> Color { entry(accentColorId).name }
}
