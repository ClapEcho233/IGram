//
//  StoryViewerSheet.swift
//  IGram
//

import AVFoundation
import AVKit
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Request to present one or more Telegram Stories in the viewer sheet.
struct StoryViewerRequest: Identifiable, Equatable {
    let id = UUID()
    /// Ordered list of poster chat IDs to step through.
    let chatIds: [Int64]
    /// Initial poster chat ID.
    let initialChatId: Int64
    /// Optional explicit story ID (when opening a specific story from a message).
    let initialStoryId: Int?
}

/// Native macOS Telegram Story viewer with segmented progress, photo & video
/// playback, reactions, story replies, and keyboard navigation.
struct StoryViewerSheet: View {
    let request: StoryViewerRequest

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.dismiss) private var dismiss

    @State private var peerIndex: Int
    @State private var storyIndex = 0
    @State private var currentStory: Story?
    @State private var isLoadingStory = false
    @State private var isPaused = false
    @State private var isMuted = false
    @State private var progress: Double = 0
    @State private var replyText = ""
    @State private var isShowingReactions = false
    @State private var isConfirmingDelete = false
    @State private var openedStory: StoryStore.StoryKey?
    @FocusState private var isReplyFocused: Bool

    private static let quickReactions = ["❤️", "🔥", "😍", "👏", "😂", "😮", "😢"]
    private static let photoDuration: Double = 5.0

    init(request: StoryViewerRequest) {
        self.request = request
        let index = request.chatIds.firstIndex(of: request.initialChatId) ?? 0
        _peerIndex = State(initialValue: index)
    }

    private var currentChatId: Int64 {
        request.chatIds.indices.contains(peerIndex) ? request.chatIds[peerIndex] : request.initialChatId
    }

    private var storyIds: [Int] {
        if let active = session.stories.activeStories(for: currentChatId), !active.stories.isEmpty {
            return active.stories.map(\.storyId)
        }
        if let explicit = request.initialStoryId, currentChatId == request.initialChatId {
            return [explicit]
        }
        return []
    }

    private var currentStoryId: Int? {
        storyIds.indices.contains(storyIndex) ? storyIds[storyIndex] : storyIds.first
    }

    private var currentStoryInfo: StoryInfo? {
        guard let storyId = currentStoryId else { return nil }
        return session.stories.activeStories(for: currentChatId)?.stories.first { $0.storyId == storyId }
    }

    private var storyDuration: Double {
        if case .storyContentVideo(let value) = currentStory?.content, value.video.duration > 0 {
            return min(max(value.video.duration, 1), 60)
        }
        return Self.photoDuration
    }

    var body: some View {
        ZStack {
            Color.black

            storyCanvas

            VStack(spacing: 0) {
                topOverlay
                Spacer(minLength: 0)
                bottomOverlay
            }

            navigationButtons
        }
        .frame(width: 440, height: 740)
        .clipShape(.rect(cornerRadius: 12))
        .onAppear {
            selectInitialStoryIndex()
        }
        .task(id: "\(currentChatId)-\(currentStoryId ?? 0)") {
            await loadAndTrackCurrentStory()
        }
        .task(id: "\(currentChatId)-\(currentStoryId ?? 0)-\(isPaused)-\(isReplyFocused)-\(isShowingReactions)") {
            await runProgressTimer()
        }
        .onDisappear {
            closeTrackedStory()
        }
        .onKeyPress(.leftArrow) {
            guard !isReplyFocused else { return .ignored }
            goPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isReplyFocused else { return .ignored }
            goNext()
            return .handled
        }
        .onKeyPress(.space) {
            guard !isReplyFocused else { return .ignored }
            isPaused.toggle()
            return .handled
        }
        .confirmationDialog("Delete this story?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Story", role: .destructive) { deleteCurrentStory() }
        }
    }

    // MARK: - Media canvas

    @ViewBuilder
    private var storyCanvas: some View {
        if let story = currentStory {
            switch story.content {
            case .storyContentPhoto(let value):
                photoContent(value.photo)
            case .storyContentVideo(let value):
                videoContent(value.video)
            case .storyContentLive:
                VStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("Live Story")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            case .storyContentUnsupported:
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("This story isn't supported yet.")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        } else if isLoadingStory {
            ProgressView()
                .tint(.white)
        } else {
            Text("Story unavailable")
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func photoContent(_ photo: Photo) -> some View {
        Group {
            if let file = photo.sizes.last?.photo {
                FileImage(file: file, maxPixelSize: 1400, priority: .media, contentMode: .fit) {
                    MinithumbnailView(minithumbnail: photo.minithumbnail)
                }
            } else {
                MinithumbnailView(minithumbnail: photo.minithumbnail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func videoContent(_ video: StoryVideo) -> some View {
        let item = session.files.item(for: video.video)
        return ZStack {
            if let url = item.localURL {
                StoryVideoPlayerView(
                    url: url,
                    isPaused: isPaused || isReplyFocused || isShowingReactions,
                    isMuted: isMuted || video.isAnimation,
                    onEnded: { goNext() }
                )
            } else {
                Group {
                    if let thumbnail = video.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
                        FileImage(file: file, maxPixelSize: 900, priority: .media, contentMode: .fit) {
                            MinithumbnailView(minithumbnail: video.minithumbnail)
                        }
                    } else {
                        MinithumbnailView(minithumbnail: video.minithumbnail)
                    }
                }
                .task(id: video.video.id) {
                    session.files.download(video.video, priority: .media)
                }
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overlays

    private var topOverlay: some View {
        VStack(spacing: 10) {
            progressBars
            HStack(spacing: 10) {
                posterAvatar
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(posterTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if currentStoryInfo?.isForCloseFriends == true {
                            Image(systemName: "star.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .help("Close Friends")
                        }
                    }
                    if let timestamp = timestampText {
                        Text(timestamp)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer(minLength: 0)

                if case .storyContentVideo(let value) = currentStory?.content, !value.video.isAnimation {
                    iconButton(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: isMuted ? "Unmute" : "Mute") {
                        isMuted.toggle()
                    }
                }

                iconButton(isPaused ? "play.fill" : "pause.fill", help: isPaused ? "Play" : "Pause") {
                    isPaused.toggle()
                }

                Menu {
                    Button("Open Chat", systemImage: "bubble.left") {
                        dismiss()
                        main.open(chatId: currentChatId)
                    }
                    if currentStory?.canBeDeleted == true {
                        Divider()
                        Button("Delete Story", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            LinearGradient(colors: [.black.opacity(0.68), .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(Array(storyIds.enumerated()), id: \.offset) { index, _ in
                GeometryReader { proxy in
                    let fill: Double = if index < storyIndex {
                        1
                    } else if index == storyIndex {
                        progress
                    } else {
                        0
                    }
                    Capsule()
                        .fill(.white.opacity(0.32))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * min(max(fill, 0), 1))
                        }
                }
                .frame(height: 2.5)
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let caption = currentStory?.caption, !caption.text.isEmpty {
                Text(caption.attributedString(linkColor: .cyan))
                    .font(.callout)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if let info = currentStory?.interactionInfo {
                    HStack(spacing: 10) {
                        Label("\(info.viewCount)", systemImage: "eye")
                        if info.reactionCount > 0 {
                            Label("\(info.reactionCount)", systemImage: "heart.fill")
                        }
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: .capsule)
                }

                if currentStory?.canBeReplied == true, currentChatId != session.myUserId {
                    TextField("Reply to story…", text: $replyText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .focused($isReplyFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.18), in: .capsule)
                        .onSubmit { sendReply() }

                    if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            sendReply()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Spacer(minLength: 0)
                }

                if let story = currentStory {
                    reactionButton(for: story)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        )
    }

    private func reactionButton(for story: Story) -> some View {
        let chosen = story.chosenReactionType
        return Button {
            if chosen != nil {
                setReaction(nil)
            } else {
                setReaction(.reactionTypeEmoji(ReactionTypeEmoji(emoji: "❤️")))
            }
        } label: {
            Group {
                if let chosen {
                    Text(ReactionActions.symbol(for: chosen))
                        .font(.title3)
                } else {
                    Image(systemName: "heart")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.18), in: .circle)
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(Self.quickReactions, id: \.self) { emoji in
                Button(emoji) {
                    setReaction(.reactionTypeEmoji(ReactionTypeEmoji(emoji: emoji)))
                }
            }
            if chosen != nil {
                Divider()
                Button("Remove Reaction") { setReaction(nil) }
            }
        }
        .help("React — right-click for more")
    }

    private var navigationButtons: some View {
        HStack {
            if canGoPrevious {
                Button { goPrevious() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.35), in: .circle)
                }
                .buttonStyle(.plain)
                .help("Previous story")
            }
            Spacer()
            Button { goNext() } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.35), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Next story")
        }
        .padding(.horizontal, 10)
    }

    private func iconButton(_ systemName: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var posterAvatar: some View {
        if let chat = session.chats.chat(currentChatId) {
            AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 32)
        } else {
            AvatarView(content: .user(session.peers.user(currentChatId).user), size: 32)
        }
    }

    private var posterTitle: String {
        if let chat = session.chats.chat(currentChatId) {
            return session.isSavedMessages(chat) ? String(localized: "My Story") : session.title(of: chat)
        }
        return session.userName(currentChatId)
    }

    private var timestampText: String? {
        guard let date = currentStory?.date ?? currentStoryInfo?.date, date > 0 else { return nil }
        return DateFormatting().chatListTimestamp(Date(timeIntervalSince1970: TimeInterval(date)))
    }

    // MARK: - Navigation & Lifecycle

    private var canGoPrevious: Bool {
        storyIndex > 0 || peerIndex > 0
    }

    private func selectInitialStoryIndex() {
        if let explicit = request.initialStoryId, let idx = storyIds.firstIndex(of: explicit) {
            storyIndex = idx
        } else if let active = session.stories.activeStories(for: currentChatId) {
            storyIndex = StoryStore.firstUnreadIndex(in: active)
        } else {
            storyIndex = 0
        }
    }

    private func goNext() {
        progress = 0
        if storyIndex + 1 < storyIds.count {
            storyIndex += 1
        } else if peerIndex + 1 < request.chatIds.count {
            peerIndex += 1
            if let active = session.stories.activeStories(for: currentChatId) {
                storyIndex = StoryStore.firstUnreadIndex(in: active)
            } else {
                storyIndex = 0
            }
        } else {
            dismiss()
        }
    }

    private func goPrevious() {
        progress = 0
        if storyIndex > 0 {
            storyIndex -= 1
        } else if peerIndex > 0 {
            peerIndex -= 1
            storyIndex = max(storyIds.count - 1, 0)
        }
    }

    private func loadAndTrackCurrentStory() async {
        closeTrackedStory()
        progress = 0
        guard let storyId = currentStoryId else {
            currentStory = nil
            return
        }
        let chatId = currentChatId
        isLoadingStory = true
        let fetched = await session.stories.fetchStory(posterChatId: chatId, storyId: storyId, api: session.api)
        guard !Task.isCancelled, currentChatId == chatId, currentStoryId == storyId else { return }
        currentStory = fetched
        isLoadingStory = false
        let key = StoryStore.StoryKey(posterChatId: chatId, storyId: storyId)
        openedStory = key
        _ = try? await session.api.openStory(storyId: storyId, storyPosterChatId: chatId)
    }

    private func closeTrackedStory() {
        guard let opened = openedStory else { return }
        openedStory = nil
        let api = session.api
        Task { _ = try? await api.closeStory(storyId: opened.storyId, storyPosterChatId: opened.posterChatId) }
    }

    private func runProgressTimer() async {
        guard !isPaused, !isReplyFocused, !isShowingReactions, currentStoryId != nil else { return }
        let step = 0.05
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            guard currentStory != nil else { continue }
            progress += step / storyDuration
            if progress >= 1 {
                goNext()
                return
            }
        }
    }

    private func setReaction(_ reaction: ReactionType?) {
        guard let storyId = currentStoryId else { return }
        let chatId = currentChatId
        let api = session.api
        Task {
            do {
                _ = try await api.setStoryReaction(
                    reactionType: reaction,
                    storyId: storyId,
                    storyPosterChatId: chatId,
                    updateRecentReactions: true
                )
            } catch {
                Log.ui.error("setStoryReaction failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    private func sendReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let storyId = currentStoryId else { return }
        let chatId = currentChatId
        replyText = ""
        isReplyFocused = false
        Task {
            do {
                _ = try await session.api.sendMessage(
                    chatId: chatId,
                    inputMessageContent: .inputMessageText(InputMessageText(
                        clearDraft: false,
                        linkPreviewOptions: nil,
                        text: FormattedText(entities: [], text: trimmed)
                    )),
                    options: nil,
                    replyMarkup: nil,
                    replyTo: .inputMessageReplyToStory(InputMessageReplyToStory(storyId: storyId, storyPosterChatId: chatId)),
                    topicId: nil
                )
                main.showToast(String(localized: "Reply sent"))
            } catch {
                main.showToast(error.telegramMessage)
            }
        }
    }

    private func deleteCurrentStory() {
        guard let storyId = currentStoryId else { return }
        let chatId = currentChatId
        Task {
            do {
                _ = try await session.api.deleteStory(storyId: storyId, storyPosterChatId: chatId)
                goNext()
            } catch {
                main.showToast(error.telegramMessage)
            }
        }
    }
}

/// Plays a video story with pause and mute synchronization.
private struct StoryVideoPlayerView: NSViewRepresentable {
    let url: URL
    let isPaused: Bool
    let isMuted: Bool
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEnded: onEnded) }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        let player = AVPlayer(url: url)
        player.isMuted = isMuted
        view.player = player
        context.coordinator.observe(player: player, url: url)
        if !isPaused { player.play() }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.onEnded = onEnded
        if context.coordinator.currentURL != url {
            let player = AVPlayer(url: url)
            player.isMuted = isMuted
            view.player = player
            context.coordinator.observe(player: player, url: url)
        }
        view.player?.isMuted = isMuted
        if isPaused {
            view.player?.pause()
        } else {
            view.player?.play()
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
        coordinator.stop()
    }

    final class Coordinator {
        var currentURL: URL?
        var onEnded: () -> Void
        private var endObserver: Any?

        init(onEnded: @escaping () -> Void) {
            self.onEnded = onEnded
        }

        func observe(player: AVPlayer, url: URL) {
            stop()
            currentURL = url
            guard let item = player.currentItem else { return }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onEnded()
                }
            }
        }

        func stop() {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
        }
    }
}
