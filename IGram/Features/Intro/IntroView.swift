//
//  IntroView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// The login flow. Each TDLib authorization state maps to one step.
struct IntroView: View {
    @Environment(TelegramSession.self) private var session
    @State private var model: IntroModel?

    var body: some View {
        ZStack {
            if let model {
                step(for: session.authorizationState, model: model)
                    .id(stepID)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth, value: stepID)
        .onAppear {
            if model == nil { model = IntroModel(session: session) }
        }
        .onChange(of: stepID) {
            model?.errorMessage = nil
        }
    }

    /// Identity of the visible step, used to animate between steps.
    private var stepID: String {
        if model?.isEditingPhoneNumber == true { return "phone" }
        switch session.authorizationState {
        case .authorizationStateWaitPhoneNumber: return "phone"
        case .authorizationStateWaitCode: return "code"
        case .authorizationStateWaitPassword: return "password"
        case .authorizationStateWaitRegistration: return "registration"
        case .authorizationStateWaitEmailAddress: return "email"
        case .authorizationStateWaitEmailCode: return "emailCode"
        case .authorizationStateWaitOtherDeviceConfirmation: return "qr"
        default: return "other"
        }
    }

    @ViewBuilder
    private func step(for state: AuthorizationState?, model: IntroModel) -> some View {
        if model.isEditingPhoneNumber {
            PhoneNumberStepView(model: model, showsQRCodeOption: false)
        } else {
            switch state {
            case .authorizationStateWaitPhoneNumber:
                PhoneNumberStepView(model: model)
            case .authorizationStateWaitCode(let value):
                CodeStepView(model: model, codeInfo: value.codeInfo)
            default:
                ContentUnavailableView(
                    "Unsupported Step",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This sign-in step is not supported yet.")
                )
            }
        }
    }
}
