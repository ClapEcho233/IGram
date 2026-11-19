//
//  RichContentViews.swift
//  IGram
//

import MapKit
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// A shared location or venue with a map preview.
struct LocationView: View {
    let location: Location
    var venue: Venue?

    @Environment(\.openURL) private var openURL

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            ))) {
                Marker(venue?.title ?? "", coordinate: coordinate)
            }
            .allowsHitTesting(false)
            .frame(width: 280, height: 160)
            .clipShape(.rect(cornerRadius: 8))
            if let venue {
                Text(venue.title).font(.callout.weight(.semibold)).lineLimit(1)
                if !venue.address.isEmpty {
                    Text(venue.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            var components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [
                URLQueryItem(name: "ll", value: "\(location.latitude),\(location.longitude)"),
                URLQueryItem(name: "q", value: venue?.title ?? String(localized: "Location")),
            ]
            if let url = components.url { openURL(url) }
        }
        .accessibilityLabel(Text(venue?.title ?? String(localized: "Location")))
    }
}

/// A shared contact card.
struct ContactView: View {
    let contact: Contact
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        let name = [contact.firstName, contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AvatarView(
                    content: contact.userId != 0
                        ? .user(session.peers.user(contact.userId).user)
                        : .photo(nil, title: name, accentColorId: Int(abs(contact.phoneNumber.hashValue) % 7)),
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? String(localized: "Contact") : name)
                        .font(.callout.weight(.semibold))
                    Text(contact.phoneNumber.hasPrefix("+") ? contact.phoneNumber : "+\(contact.phoneNumber)")
                        .font(.caption)
                        .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))
                        .textSelection(.enabled)
                }
            }
            if contact.userId != 0 {
                Button("Send Message") {
                    Task {
                        if let chat = try? await session.api.createPrivateChat(force: false, userId: contact.userId) {
                            main.open(chatId: chat.id)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(minWidth: 200, alignment: .leading)
    }
}

/// A poll or quiz with voting, after tdesktop's `HistoryView::Poll`.
struct PollView: View {
    let message: ChatMessage
    let poll: Poll
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session
    @Environment(\.chatThemeStyle) private var theme
    @State private var selection: Set<Int> = []

    private var hasVoted: Bool { poll.options.contains { $0.isChosen } }
    private var showsResults: Bool { hasVoted || poll.isClosed || poll.canSeeResults && message.isOutgoing }
    private var isQuiz: Bool {
        if case .pollTypeQuiz = poll.type { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(poll.question.attributedString())
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(kindText)
                .font(.caption)
                .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))

            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                if showsResults {
                    result(option)
                } else {
                    choice(option, index: index)
                }
            }

            HStack {
                Text(poll.totalVoterCount == 0 ? String(localized: "No votes yet") : String(localized: "\(poll.totalVoterCount) votes"))
                    .font(.caption)
                    .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))
                Spacer()
                if poll.allowsMultipleAnswers, !showsResults {
                    Button("Vote") { vote(Array(selection).sorted()) }
                        .controlSize(.small)
                        .disabled(selection.isEmpty)
                } else if hasVoted, !poll.isClosed, !isQuiz {
                    Button("Retract Vote") { vote([]) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .frame(width: 300, alignment: .leading)
    }

    private var kindText: String {
        if poll.isClosed { return String(localized: "Final results") }
        if isQuiz { return poll.isAnonymous ? String(localized: "Anonymous Quiz") : String(localized: "Quiz") }
        return poll.isAnonymous ? String(localized: "Anonymous Poll") : String(localized: "Public Poll")
    }

    private func choice(_ option: PollOption, index: Int) -> some View {
        Button {
            if poll.allowsMultipleAnswers {
                if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
            } else {
                vote([index])
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selection.contains(index) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(theme.accent(outgoing: isOutgoingStyle))
                Text(option.text.attributedString())
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if option.isBeingChosen { ProgressView().controlSize(.mini) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func result(_ option: PollOption) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("\(option.votePercentage)%")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .frame(width: 42, alignment: .leading)
                Text(option.text.attributedString())
                    .font(.callout)
                if option.isChosen {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent(outgoing: isOutgoingStyle))
                        .font(.caption)
                }
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(theme.accent(outgoing: isOutgoingStyle))
                    .frame(width: max(proxy.size.width * CGFloat(option.votePercentage) / 100, 4))
            }
            .frame(height: 4)
            .padding(.leading, 48)
        }
    }

    private func vote(_ indices: [Int]) {
        let chatId = message.chatId
        let messageId = message.id
        let api = session.api
        Task {
            do {
                try await api.setPollAnswer(chatId: chatId, messageId: messageId, optionIds: indices)
                selection = []
            } catch {
                Log.ui.error("Vote failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}

/// A call log entry.
struct CallView: View {
    let call: MessageCall
    let isOutgoing: Bool
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session
    @Environment(\.chatThemeStyle) private var theme

    private var isMissed: Bool {
        switch call.discardReason {
        case .callDiscardReasonMissed, .callDiscardReasonDeclined: true
        default: false
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: call.isVideo ? "video.fill" : "phone.fill")
                .font(.title3)
                .foregroundStyle(theme.accent(outgoing: isOutgoingStyle))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                HStack(spacing: 3) {
                    Image(systemName: isOutgoing ? "arrow.up.right" : "arrow.down.left")
                        .foregroundStyle(isMissed ? .red : .green)
                    if call.duration > 0 {
                        Text(DurationFormatting.short(call.duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))
            }
        }
        .frame(minWidth: 160, alignment: .leading)
    }

    private var title: String {
        if isMissed {
            return isOutgoing ? String(localized: "Cancelled call") : session.formatter().callDescription(call)
        }
        if call.isVideo {
            return isOutgoing ? String(localized: "Outgoing video call") : String(localized: "Incoming video call")
        }
        return isOutgoing ? String(localized: "Outgoing call") : String(localized: "Incoming call")
    }
}
