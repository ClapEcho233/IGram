# IGram

A native macOS Telegram client written in Swift and SwiftUI, modeled on
[Telegram Desktop](https://github.com/telegramdesktop/tdesktop) (tdesktop).

tdesktop is a C++/Qt application with its own MTProto stack. IGram keeps
tdesktop's structure and behavior but rebuilds the UI natively, and delegates
the protocol, local database and update sequencing to
[TDLib](https://github.com/tdlib/td), Telegram's official client library, through
the [TDLibKit](https://github.com/Swiftgram/TDLibKit) Swift package.

## Requirements

- macOS 27 and Xcode 27
- A Telegram API ID and hash of your own

## Getting started

1. Create an application at <https://my.telegram.org/apps> to get an
   `api_id` and `api_hash`. Telegram requires every third-party client to use
   its own pair, so IGram doesn't ship one (tdesktop compiles its own in).
2. Open `IGram.xcodeproj` and run the **IGram** scheme. Xcode resolves TDLibKit
   on the first build; TDLibKit is a large module, so that build takes a while.
3. Paste your API ID and hash on the welcome screen, or set the `TG_API_ID` and
   `TG_API_HASH` environment variables in the scheme (`TG_TEST_DC=1` selects
   Telegram's test servers).

Run the unit tests with:

```bash
xcodebuild -project IGram.xcodeproj -scheme IGram -destination 'platform=macOS' -only-testing:IGramTests -testLanguage en test
```

## Architecture

| tdesktop (`Telegram/SourceFiles`) | IGram |
| --- | --- |
| `mtproto/`, `storage/` | TDLib via `Core/TDLib/TelegramClient` |
| `main/main_session`, `data/data_session` | `Core/Session/TelegramSession` plus the stores in `Data/` |
| `dialogs/` (chat list, folders, search) | `Features/Dialogs`, `Features/Main` |
| `history/` (messages, composer) | `Features/History`, `Features/Composer` |
| `info/` (profile panel) | `Features/Info` |
| `intro/` (login) | `Features/Intro` |
| `settings/` | `Features/Settings` |
| `window/notifications_*` | `Features/Notifications` |
| `media/player` | `Features/Media/AudioPlayer` |

- **TelegramClient** owns one TDLib JSON client and turns its updates into an
  ordered `AsyncStream`.
- **TelegramSession** applies every update on the main actor and routes it to
  the stores: `PeerStore` (users, groups), `ChatStore` with ordered
  `ChatListModel`s, `FileStore`, `ChatFolderStore`, `ThemeStore`, `StoryStore`,
  and the `HistoryModel` of each open chat. Stores hand out one `@Observable`
  item per entity, so a view only refreshes when the thing it shows changes.
- TDLib's generated models are immutable, so `ChatItem` and `ChatMessage` keep
  the fields TDLib patches after delivery.
- TDLibKit declares types such as `Date`, `Text` and `Error`; the module-level
  aliases in `Core/TypeAliases.swift` make the Apple types win inside IGram.

## Features

- Login: phone number with country detection, code (every delivery type, resend
  countdown), two-step verification password with recovery, sign-up, login
  email, and QR code login
- Chat list: Messages-style sidebar with folder tabs above it, archive, pinned chats, unread, mention and
  reaction badges, delivery checks, drafts and typing status, paging, plus a
  context menu to pin, mute, archive, mark read or unread, delete or leave
- History: Messages-style blue and gray bubbles with tails on the window
  background by default (tdesktop's wallpaper themes remain under Appearance),
  grouped like tdesktop, day headers that stay pinned while scrolling, large
  emoji-only messages, sent and read checks, unread bar, replies and
  forwards, opening at the first unread message, jumping to any message,
  reactions, and a context menu to reply, edit, copy, copy link, pin, forward,
  save and delete
- Content: text with formatting and links, photos, videos, GIFs, albums,
  stickers, animated emoji, dice, round videos, files, music, voice messages
  with waveforms, locations, contacts, polls with voting, calls, and service
  messages
- Composer: Return or ⌘Return to send, ↑ to edit your last message, Esc to
  cancel, Markdown shortcuts, cloud drafts, attachments from the picker, drag
  and drop or paste, and albums
- Chat info inspector with members and shared media; global and in-chat search
- Settings: account, notifications, appearance, active sessions, storage and
  log out; system notifications and a Dock badge; keyboard shortcuts in the
  Chats menu (⌘0 Saved Messages, ⌘1–9 folders, ⌥⌘↑/↓ to switch chats)

- Also: link previews, pinned-message bar, unread mention/reaction jumps,
  bot inline and reply keyboards, embedded bot Web Apps (`WKWebView` with
  `TelegramWebviewProxy` bridge, theme/viewport sync, MainButton/BackButton,
  popups and custom requests), full `@bot query` inline bot results for all
  result types, multi-select, silent and scheduled sending, voice message
  recording (Ogg Opus), emoji/sticker/GIF panel with animated (Lottie) and
  video (WebM VP9 + alpha via VideoToolbox) stickers, sticker pack preview and
  installation, @mention, inline bot and /command autocomplete, Telegram
  Stories (stories bar, avatar rings, photo & video viewer with reactions and
  replies), chat themes, presets and cloud/custom wallpapers, new
  groups/channels/secret chats and contacts, group editing and member
  management, folder editor, forum topics, privacy and two-step verification,
  proxies, full `t.me`/`tg://` deep link routing (including invite links and
  message links), up to three accounts with cross-account notifications and
  Dock badge, and Simplified Chinese (656 strings)

## Not yet implemented

Voice and video calls (tdesktop uses tgcalls/WebRTC, which has no Swift port).
