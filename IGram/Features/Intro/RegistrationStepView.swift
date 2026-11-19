//
//  RegistrationStepView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Sign-up for new phone numbers, like tdesktop's `Intro::SignupWidget`.
struct RegistrationStepView: View {
    @Bindable var model: IntroModel
    let termsOfService: TermsOfService

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isShowingTerms = false
    @FocusState private var focusedField: Field?

    private enum Field { case first, last }

    var body: some View {
        IntroStepLayout(
            systemImage: "person.crop.circle.badge.plus",
            title: String(localized: "Your Info"),
            subtitle: String(localized: "Please enter your name."),
            errorMessage: model.errorMessage
        ) {
            TextField("First name", text: $firstName)
                .textFieldStyle(IntroTextFieldStyle())
                .textContentType(.givenName)
                .focused($focusedField, equals: .first)
                .onSubmit { focusedField = .last }
            TextField("Last name (optional)", text: $lastName)
                .textFieldStyle(IntroTextFieldStyle())
                .textContentType(.familyName)
                .focused($focusedField, equals: .last)
                .onSubmit(submit)
        } actions: {
            IntroPrimaryButton(
                title: String(localized: "Sign Up"),
                isBusy: model.isBusy,
                isDisabled: firstName.trimmingCharacters(in: .whitespaces).isEmpty,
                action: submit
            )
            Button("By signing up, you agree to the Terms of Service") { isShowingTerms = true }
                .buttonStyle(.link)
                .font(.callout)
        }
        .onAppear {
            focusedField = .first
            if termsOfService.showPopup { isShowingTerms = true }
        }
        .sheet(isPresented: $isShowingTerms) {
            TermsOfServiceSheet(terms: termsOfService)
        }
    }

    private func submit() {
        Task { await model.register(firstName: firstName, lastName: lastName) }
    }
}

private struct TermsOfServiceSheet: View {
    let terms: TermsOfService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Terms of Service")
                .font(.title2.bold())
            ScrollView {
                Text(terms.text.attributedString())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if terms.minUserAge > 0 {
                Text("You must be at least \(terms.minUserAge) years old to use Telegram.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460, height: 420)
    }
}
