//
//  IGramApp.swift
//  IGram
//

import AppKit
import SwiftUI

@main
struct IGramApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()

    var body: some Scene {
        Window("IGram", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear { appDelegate.app = app }
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppModel?

    func applicationWillTerminate(_ notification: Notification) {
        app?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
