//
//  IntroStepLayout.swift
//  IGram
//

import SwiftUI

/// The common layout of a login step: icon, title, description, fields and actions.
struct IntroStepLayout<Content: View, Actions: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var errorMessage: String?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .frame(height: 64)
            VStack(spacing: 8) {
                Text(title)
                    .font(.title.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                content
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            VStack(spacing: 10) {
                actions
            }
        }
        .frame(width: 340)
        .padding(32)
        .animation(.default, value: errorMessage)
    }
}

/// Large rounded text field used on login steps.
struct IntroTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.title3)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
    }
}

/// The prominent "Next" button of a step, showing progress while busy.
struct IntroPrimaryButton: View {
    let title: String
    var isBusy = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(isBusy || isDisabled)
    }
}
