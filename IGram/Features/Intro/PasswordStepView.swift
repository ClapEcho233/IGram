//
//  PasswordStepView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Two-step verification password, like tdesktop's `Intro::PasswordCheckWidget`.
struct PasswordStepView: View {
    @Bindable var model: IntroModel
    let state: AuthorizationStateWaitPassword

    @State private var password = ""
    @State private var recoveryCode = ""
    @State private var newPassword = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if model.isRecoveringPassword {
            recovery
        } else {
            check
        }
    }

    private var check: some View {
        IntroStepLayout(
            systemImage: "lock.fill",
            title: String(localized: "Two-Step Verification"),
            subtitle: String(localized: "Your account is protected with an additional password."),
            errorMessage: model.errorMessage
        ) {
            SecureField("Password", text: $password, prompt: Text(state.passwordHint.isEmpty ? String(localized: "Password") : state.passwordHint))
                .textFieldStyle(IntroTextFieldStyle())
                .textContentType(.password)
                .focused($isFocused)
                .onSubmit(submit)
            if !state.passwordHint.isEmpty {
                Text("Hint: \(state.passwordHint)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            IntroPrimaryButton(
                title: String(localized: "Next"),
                isBusy: model.isBusy,
                isDisabled: password.isEmpty,
                action: submit
            )
            if state.hasRecoveryEmailAddress {
                Button("Forgot password?") {
                    Task { await model.requestPasswordRecovery() }
                }
                .buttonStyle(.link)
                .disabled(model.isBusy)
            }
            Button("Wrong number?") { model.isEditingPhoneNumber = true }
                .buttonStyle(.link)
        }
        .onAppear { isFocused = true }
    }

    private var recovery: some View {
        IntroStepLayout(
            systemImage: "envelope.badge.shield.half.filled",
            title: String(localized: "Password Recovery"),
            subtitle: String(localized: "We've sent a recovery code to \(state.recoveryEmailAddressPattern). You can set a new password or leave it empty to turn the password off."),
            errorMessage: model.errorMessage
        ) {
            TextField("Recovery code", text: $recoveryCode)
                .textFieldStyle(IntroTextFieldStyle())
                .textContentType(.oneTimeCode)
                .focused($isFocused)
            SecureField("New password (optional)", text: $newPassword)
                .textFieldStyle(IntroTextFieldStyle())
                .textContentType(.newPassword)
        } actions: {
            IntroPrimaryButton(
                title: String(localized: "Recover"),
                isBusy: model.isBusy,
                isDisabled: recoveryCode.isEmpty
            ) {
                Task { await model.recoverPassword(code: recoveryCode, newPassword: newPassword, hint: "") }
            }
            Button("Back") { model.cancelPasswordRecovery() }
                .buttonStyle(.link)
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        Task { await model.submitPassword(password) }
    }
}
