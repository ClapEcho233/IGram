//
//  APISetupView.swift
//  IGram
//

import SwiftUI

/// First-launch screen asking for the Telegram API credentials.
struct APISetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var apiId = ""
    @State private var apiHash = ""
    @State private var useTestDC = false

    private var credentials: APICredentials? {
        guard let id = Int(apiId.trimmingCharacters(in: .whitespaces)) else { return nil }
        let value = APICredentials(apiId: id, apiHash: apiHash, useTestDC: useTestDC)
        return value.isValid ? value : nil
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Welcome to IGram")
                    .font(.largeTitle.bold())
                Text("IGram needs its own Telegram API ID and hash. Create an application at my.telegram.org, then paste the values below.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
            }

            Form {
                TextField("API ID", text: $apiId, prompt: Text(verbatim: "1234567"))
                TextField("API hash", text: $apiHash, prompt: Text(verbatim: "0123456789abcdef0123456789abcdef"))
                    .font(.body.monospaced())
                Toggle("Use test servers", isOn: $useTestDC)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 460)
            .onSubmit(submit)

            HStack {
                Button("Open my.telegram.org") { openURL(APICredentials.registrationURL) }
                Spacer()
                Button("Continue", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(credentials == nil)
            }
            .frame(maxWidth: 440)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard let credentials else { return }
        app.useCredentials(credentials)
    }
}

#Preview {
    APISetupView()
        .environment(AppModel(credentials: CredentialsStore(defaults: UserDefaults(suiteName: "preview")!, environment: [:])))
}
