//
//  RootView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Chooses between API setup, the login flow and the main window.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.credentials.credentials == nil {
                APISetupView()
            } else if let session = app.session {
                SessionRootView(session: session)
                    .environment(session)
                    .id(ObjectIdentifier(session))
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }
}

/// The stage of a session as far as the UI is concerned.
enum SessionPhase: Equatable {
    case starting
    case authorizing
    case ready
    case closing
}

extension TelegramSession {
    var phase: SessionPhase {
        switch authorizationState {
        case nil, .authorizationStateWaitTdlibParameters:
            .starting
        case .authorizationStateReady:
            .ready
        case .authorizationStateLoggingOut, .authorizationStateClosing, .authorizationStateClosed:
            .closing
        default:
            .authorizing
        }
    }
}

private struct SessionRootView: View {
    let session: TelegramSession

    var body: some View {
        switch session.phase {
        case .starting:
            StartupView(error: session.startupError)
        case .authorizing:
            IntroView()
        case .ready:
            MainView()
        case .closing:
            ProgressView("Logging out…")
                .controlSize(.large)
        }
    }
}

/// Shown while TDLib opens its database.
private struct StartupView: View {
    @Environment(AppModel.self) private var app
    let error: String?

    var body: some View {
        VStack(spacing: 16) {
            if let error {
                ContentUnavailableView {
                    Label("Couldn't Start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Change API Credentials…") { app.resetCredentials() }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Connecting…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
