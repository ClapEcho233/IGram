//
//  CodeStepView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Confirmation code entry, like tdesktop's `Intro::CodeWidget`.
struct CodeStepView: View {
    @Bindable var model: IntroModel
    let codeInfo: AuthenticationCodeInfo

    @State private var code = ""
    @State private var resendDeadline: Date?
    @FocusState private var isFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        IntroStepLayout(
            systemImage: "ellipsis.message",
            title: codeInfo.phoneNumber.isEmpty ? String(localized: "Enter Code") : "+\(codeInfo.phoneNumber.filter(\.isNumber))",
            subtitle: Self.description(of: codeInfo.type),
            errorMessage: model.errorMessage
        ) {
            TextField("Code", text: $code, prompt: Text(placeholder))
                .textFieldStyle(IntroTextFieldStyle())
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .onSubmit(submit)
                .onChange(of: code) { _, newValue in
                    if let length = expectedLength, newValue.filter(\.isNumber).count == length {
                        submit()
                    }
                }

            if case .authenticationCodeTypeFragment(let fragment) = codeInfo.type,
               let url = URL(string: fragment.url) {
                Button("Open Fragment") { openURL(url) }
                    .buttonStyle(.link)
            }
        } actions: {
            IntroPrimaryButton(
                title: String(localized: "Next"),
                isBusy: model.isBusy,
                isDisabled: code.isEmpty,
                action: submit
            )
            resendButton
            Button("Wrong number?") { model.isEditingPhoneNumber = true }
                .buttonStyle(.link)
        }
        .onAppear {
            isFocused = true
            resetResendDeadline()
        }
        .onChange(of: codeInfo) {
            resetResendDeadline()
        }
    }

    /// Restarts the countdown whenever TDLib sends a new code.
    private func resetResendDeadline() {
        resendDeadline = codeInfo.timeout > 0 ? .now.addingTimeInterval(TimeInterval(codeInfo.timeout)) : nil
    }

    @ViewBuilder
    private var resendButton: some View {
        if let next = codeInfo.nextType {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = resendDeadline.map { Int($0.timeIntervalSince(context.date).rounded(.up)) } ?? 0
                if remaining > 0 {
                    Text("\(Self.resendTitle(for: next)) in \(DurationFormatting.short(remaining))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button(Self.resendTitle(for: next)) {
                        code = ""
                        Task { await model.resendCode() }
                    }
                    .buttonStyle(.link)
                    .disabled(model.isBusy)
                }
            }
        }
    }

    private var expectedLength: Int? {
        switch codeInfo.type {
        case .authenticationCodeTypeTelegramMessage(let value): value.length
        case .authenticationCodeTypeSms(let value): value.length
        case .authenticationCodeTypeCall(let value): value.length
        case .authenticationCodeTypeMissedCall(let value): value.length
        case .authenticationCodeTypeFragment(let value): value.length
        default: nil
        }
    }

    private var placeholder: String {
        expectedLength.map { String(repeating: "–", count: $0) } ?? String(localized: "Code")
    }

    private func submit() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !model.isBusy else { return }
        Task { await model.submitCode(trimmed) }
    }

    static func description(of type: AuthenticationCodeType) -> String {
        switch type {
        case .authenticationCodeTypeTelegramMessage:
            String(localized: "We've sent the code to the Telegram app on your other device.")
        case .authenticationCodeTypeSms:
            String(localized: "We've sent you an SMS with the code.")
        case .authenticationCodeTypeSmsWord(let value):
            String(localized: "Enter the word from the SMS we sent you. It starts with “\(value.firstLetter)”.")
        case .authenticationCodeTypeSmsPhrase(let value):
            String(localized: "Enter the phrase from the SMS we sent you. It starts with “\(value.firstWord)”.")
        case .authenticationCodeTypeCall:
            String(localized: "We're calling your phone to dictate the code.")
        case .authenticationCodeTypeFlashCall:
            String(localized: "We're calling your phone. Enter the number that called you.")
        case .authenticationCodeTypeMissedCall(let value):
            String(localized: "We've called you from +\(value.phoneNumberPrefix)… Enter the last \(value.length) digits of that number.")
        case .authenticationCodeTypeFragment:
            String(localized: "We've sent the code to your anonymous number on Fragment.")
        case .authenticationCodeTypeFirebaseAndroid, .authenticationCodeTypeFirebaseIos:
            String(localized: "We've sent you an SMS with the code.")
        }
    }

    static func resendTitle(for type: AuthenticationCodeType) -> String {
        switch type {
        case .authenticationCodeTypeSms, .authenticationCodeTypeSmsWord, .authenticationCodeTypeSmsPhrase:
            String(localized: "Send code via SMS")
        case .authenticationCodeTypeCall, .authenticationCodeTypeFlashCall, .authenticationCodeTypeMissedCall:
            String(localized: "Call me instead")
        case .authenticationCodeTypeFragment:
            String(localized: "Send code via Fragment")
        default:
            String(localized: "Resend code")
        }
    }
}
