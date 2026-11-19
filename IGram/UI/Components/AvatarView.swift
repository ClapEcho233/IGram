//
//  AvatarView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// What an avatar represents.
enum AvatarContent: Equatable {
    case photo(ChatPhotoInfo?, title: String, accentColorId: Int)
    case savedMessages
    case deletedAccount

    static func chat(_ chat: ChatItem, myUserId: Int64) -> AvatarContent {
        if chat.userId == myUserId, !chat.isSecret { return .savedMessages }
        return .photo(chat.photo, title: chat.title, accentColorId: chat.accentColorId)
    }

    static func user(_ user: User?) -> AvatarContent {
        guard let user else { return .photo(nil, title: "", accentColorId: 0) }
        if user.isDeleted { return .deletedAccount }
        let photo = user.profilePhoto.map {
            ChatPhotoInfo(big: $0.big, hasAnimation: $0.hasAnimation, isPersonal: $0.isPersonal, minithumbnail: $0.minithumbnail, small: $0.small)
        }
        return .photo(photo, title: user.fullName, accentColorId: user.accentColorId)
    }
}

/// A circular peer avatar: photo, or initials on the peer color like tdesktop's
/// `Ui::EmptyUserpic`.
struct AvatarView: View {
    let content: AvatarContent
    var size: CGFloat = 44
    var isOnline = false

    var body: some View {
        avatar
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay(alignment: .bottomTrailing) {
                if isOnline {
                    Circle()
                        .fill(.green)
                        .frame(width: size * 0.28, height: size * 0.28)
                        .overlay(Circle().stroke(.background, lineWidth: max(size * 0.05, 1.5)))
                        .offset(x: -size * 0.02, y: -size * 0.02)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatar: some View {
        switch content {
        case .savedMessages:
            ZStack {
                PeerColor.gradient(5)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
            }
        case .deletedAccount:
            ZStack {
                Color.gray.opacity(0.6)
                Image(systemName: "person.fill.xmark")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
            }
        case .photo(let photo, let title, let accentColorId):
            let initials = Self.initials(title)
            let fallback = ZStack {
                PeerColor.gradient(accentColorId)
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            if let photo {
                FileImage(file: photo.small, maxPixelSize: Int(size * 3), priority: .thumbnail) {
                    if let mini = photo.minithumbnail {
                        MinithumbnailView(minithumbnail: mini)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
    }

    /// Up to two initials from the first and last words, as tdesktop does.
    static func initials(_ title: String) -> String {
        let words = title
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        guard let first = words.first?.first else {
            return title.first.map { String($0).uppercased() } ?? ""
        }
        if words.count > 1, let last = words.last?.first {
            return (String(first) + String(last)).uppercased()
        }
        return String(first).uppercased()
    }
}

/// The unread counter shown in chat rows and folders.
struct UnreadBadge: View {
    let count: Int
    var isMuted = false
    var isMarkedUnread = false

    var body: some View {
        Text(count > 0 ? Self.format(count) : " ")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 6 : 0)
            .frame(minWidth: 20, minHeight: 20)
            .background(isMuted ? AnyShapeStyle(Color.gray.opacity(0.7)) : AnyShapeStyle(.tint), in: .capsule)
            .accessibilityLabel(Text("\(count) unread"))
    }

    static func format(_ count: Int) -> String {
        switch count {
        case ..<1000: "\(count)"
        case ..<10_000: String(format: "%.1fK", Double(count) / 1000).replacingOccurrences(of: ".0K", with: "K")
        default: "\(count / 1000)K"
        }
    }
}
