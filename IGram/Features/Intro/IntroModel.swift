//
//  IntroModel.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Drives the login steps, mirroring tdesktop's `Intro::Widget` and its steps.
///
/// The current step is TDLib's authorization state; this model only performs
/// the requests and keeps transient UI state such as errors.
@Observable
final class IntroModel {
    private(set) var isBusy = false
    var errorMessage: String?
    /// Set when the user chose "Change number" on the code or password step.
    var isEditingPhoneNumber = false
    private(set) var countries: [CountryInfo] = []
    private(set) var detectedCountry: CountryInfo?

    @ObservationIgnored private let session: TelegramSession
    private var api: TDLibClient { session.api }

    init(session: TelegramSession) {
        self.session = session
    }

    /// Runs a request, tracking the busy state and surfacing its error.
    private func perform(_ request: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await request()
        } catch {
            errorMessage = error.telegramMessage
            Log.session.error("Login step failed: \(error.telegramMessage, privacy: .public)")
        }
    }

    // MARK: - Phone number

    func loadCountries() async {
        guard countries.isEmpty else { return }
        if let result = try? await api.getCountries() {
            countries = result.countries
                .filter { !$0.isHidden }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        if let code = try? await api.getCountryCode() {
            detectedCountry = countries.first { $0.countryCode == code.text }
        }
    }

    /// Looks up the country for a partially typed number.
    func phoneNumberInfo(for prefix: String) async -> PhoneNumberInfo? {
        let digits = prefix.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return try? await api.getPhoneNumberInfo(phoneNumberPrefix: digits)
    }

    func submitPhoneNumber(_ phoneNumber: String) async {
        let digits = phoneNumber.filter(\.isNumber)
        guard digits.count >= 5 else {
            errorMessage = String(localized: "Please enter a valid phone number.")
            return
        }
        await perform {
            try await self.api.setAuthenticationPhoneNumber(phoneNumber: "+" + digits, settings: nil)
            self.isEditingPhoneNumber = false
        }
    }

    // MARK: - Code

    func submitCode(_ code: String) async {
        await perform { try await self.api.checkAuthenticationCode(code: code) }
    }

    func resendCode() async {
        await perform { try await self.api.resendAuthenticationCode(reason: .resendCodeReasonUserRequest) }
    }

    // MARK: - Password

    func submitPassword(_ password: String) async {
        await perform { try await self.api.checkAuthenticationPassword(password: password) }
    }

    // MARK: - Registration

    func register(firstName: String, lastName: String) async {
        let first = firstName.trimmingCharacters(in: .whitespaces)
        guard !first.isEmpty else {
            errorMessage = String(localized: "Please enter your first name.")
            return
        }
        await perform {
            try await self.api.registerUser(
                disableNotification: false,
                firstName: first,
                lastName: lastName.trimmingCharacters(in: .whitespaces)
            )
        }
    }

    // MARK: - Email

    func submitEmailAddress(_ email: String) async {
        await perform { try await self.api.setAuthenticationEmailAddress(emailAddress: email) }
    }

    func submitEmailCode(_ code: String) async {
        await perform {
            try await self.api.checkAuthenticationEmailCode(
                code: .emailAddressAuthenticationCode(EmailAddressAuthenticationCode(code: code))
            )
        }
    }

    // MARK: - QR code

    func requestQRCode() async {
        await perform { try await self.api.requestQrCodeAuthentication(otherUserIds: []) }
    }

    /// TDLib cannot leave QR login for phone login, so reset the unauthorized
    /// client; the new one starts at the phone number step.
    func cancelQRCode() async {
        await perform { try await self.api.logOut() }
    }
}
