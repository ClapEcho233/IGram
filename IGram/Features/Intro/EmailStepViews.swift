//
//  EmailStepViews.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Email address required by Telegram for some new logins.
struct EmailAddressStepView: View {
    @Bindable var model: IntroModel

    @State private var email = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        IntroStepLayout(
            systemImage: "envelope.fill",
            title: String(localized: "Choose a Login Email"),
            subtitle: String(localized: "Telegram will send login codes to this email address instead of SMS."),
            errorMessage: model.errorMessage
        ) {
            TextField("Email", text: $email, prompt: Text(verbatim: "name@example.com"))
                .textFieldStyle(IntroTextFieldStyle())
                .textContentType(.emailAddress)
                .focused($isFocused)
                .onSubmit(submit)
        } actions: {
            IntroPrimaryButton(
                title: String(localized: "Next"),
                isBusy: model.isBusy,
                isDisabled: !email.contains("@"),
                action: submit
            )
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        Task { await model.submitEmailAddress(email.trimmingCharacters(in: .whitespaces)) }
    }
}

/// Code sent to the login email address.
struct EmailCodeStepView: View {
    @Bindable var model: IntroModel
    let state: AuthorizationStateWaitEmailCode

    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        IntroStepLayout(
            systemImage: "envelope.open.fill",
            title: String(localized: "Check Your Email"),
            subtitle: String(localized: "Please enter the code we've sent to \(state.codeInfo.emailAddressPattern)."),
            errorMessage: model.errorMessage
        ) {
            TextField("Code", text: $code, prompt: Text(String(repeating: "–", count: max(state.codeInfo.length, 1))))
                .textFieldStyle(IntroTextFieldStyle())
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .onSubmit(submit)
                .onChange(of: code) { _, newValue in
                    if state.codeInfo.length > 0, newValue.count == state.codeInfo.length { submit() }
                }
        } actions: {
            IntroPrimaryButton(
                title: String(localized: "Next"),
                isBusy: model.isBusy,
                isDisabled: code.isEmpty,
                action: submit
            )
            Button("Wrong number?") { model.isEditingPhoneNumber = true }
                .buttonStyle(.link)
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !code.isEmpty, !model.isBusy else { return }
        Task { await model.submitEmailCode(code) }
    }
}
