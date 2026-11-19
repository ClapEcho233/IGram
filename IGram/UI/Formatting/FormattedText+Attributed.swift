//
//  FormattedText+Attributed.swift
//  IGram
//

import Foundation
import SwiftUI
@preconcurrency import TDLibKit

/// Links inside message text that IGram handles itself rather than the browser.
enum InternalLink: Equatable {
    case user(Int64)
    case username(String)
    case hashtag(String)
    case botCommand(String)

    static let scheme = "igram"

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .user(let id):
            components.host = "user"
            components.path = "/\(id)"
        case .username(let name):
            components.host = "username"
            components.path = "/\(name)"
        case .hashtag(let tag):
            components.host = "hashtag"
            components.path = "/\(tag)"
        case .botCommand(let command):
            components.host = "botcommand"
            components.path = "/\(command)"
        }
        return components.url
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let value = String(url.path(percentEncoded: false).dropFirst())
        switch host {
        case "user":
            guard let id = Int64(value) else { return nil }
            self = .user(id)
        case "username": self = .username(value)
        case "hashtag": self = .hashtag(value)
        case "botcommand": self = .botCommand(value)
        default: return nil
        }
    }
}

extension FormattedText {
    /// Converts TDLib entities to an `AttributedString` for SwiftUI `Text`.
    ///
    /// Entity offsets and lengths are measured in UTF-16 code units, the same
    /// convention tdesktop's `TextWithEntities` uses.
    func attributedString(linkColor: Color? = nil) -> AttributedString {
        var result = AttributedString(text)
        let utf16 = text.utf16
        for entity in entities {
            guard entity.length > 0,
                  let start = utf16.index(utf16.startIndex, offsetBy: entity.offset, limitedBy: utf16.endIndex),
                  let end = utf16.index(start, offsetBy: entity.length, limitedBy: utf16.endIndex),
                  let range = Range<AttributedString.Index>(start..<end, in: result)
            else { continue }
            let substring = String(text[start..<end])
            apply(entity.type, substring: substring, to: &result[range], linkColor: linkColor)
        }
        return result
    }

    private func apply(
        _ type: TextEntityType,
        substring: String,
        to slice: inout AttributedSubstring,
        linkColor: Color?
    ) {
        func link(_ url: URL?) {
            guard let url else { return }
            slice.link = url
            if let linkColor { slice.foregroundColor = linkColor }
        }

        func addIntent(_ intent: InlinePresentationIntent) {
            slice.inlinePresentationIntent = (slice.inlinePresentationIntent ?? []).union(intent)
        }

        switch type {
        case .textEntityTypeBold:
            addIntent(.stronglyEmphasized)
        case .textEntityTypeItalic:
            addIntent(.emphasized)
        case .textEntityTypeUnderline:
            slice.underlineStyle = .single
        case .textEntityTypeStrikethrough:
            slice.strikethroughStyle = .single
        case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
            addIntent(.code)
        case .textEntityTypeSpoiler:
            slice.foregroundColor = .gray
            slice.backgroundColor = .gray
        case .textEntityTypeBlockQuote, .textEntityTypeExpandableBlockQuote:
            addIntent(.emphasized)
        case .textEntityTypeUrl:
            link(Self.webURL(from: substring))
        case .textEntityTypeTextUrl(let value):
            link(Self.webURL(from: value.url))
        case .textEntityTypeEmailAddress:
            link(URL(string: "mailto:\(substring)"))
        case .textEntityTypePhoneNumber:
            link(URL(string: "tel:\(substring.filter { $0.isNumber || $0 == "+" })"))
        case .textEntityTypeMention:
            link(InternalLink.username(String(substring.drop { $0 == "@" })).url)
        case .textEntityTypeMentionName(let value):
            link(InternalLink.user(value.userId).url)
        case .textEntityTypeHashtag, .textEntityTypeCashtag:
            link(InternalLink.hashtag(substring).url)
        case .textEntityTypeBotCommand:
            link(InternalLink.botCommand(substring).url)
        default:
            break
        }
    }

    /// Adds `https://` to bare domains such as `telegram.org`.
    static func webURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty, trimmed.contains("://") || scheme == "tg" {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    var isEmpty: Bool { text.isEmpty }
}
