//
//  PhoneNumberStepView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Phone number entry with country detection, like tdesktop's `Intro::PhoneWidget`.
struct PhoneNumberStepView: View {
    @Bindable var model: IntroModel
    var showsQRCodeOption = true

    @State private var phoneNumber = ""
    @State private var matchedCountry: CountryInfo?
    @State private var formattedNumber = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        IntroStepLayout(
            systemImage: "paperplane.fill",
            title: String(localized: "Your Phone Number"),
            subtitle: String(localized: "Please confirm your country code and enter your phone number."),
            errorMessage: model.errorMessage
        ) {
            Menu {
                ForEach(model.countries, id: \.countryCode) { country in
                    Button("\(country.flagEmoji) \(country.name)  +\(country.callingCodes.first ?? "")") {
                        select(country)
                    }
                }
            } label: {
                Text(matchedCountry.map { "\($0.flagEmoji) \($0.name)" } ?? String(localized: "Choose a country"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.button)

            TextField("Phone number", text: $phoneNumber, prompt: Text(verbatim: "+1 234 567 8900"))
                .textFieldStyle(IntroTextFieldStyle())
                .textContentType(.telephoneNumber)
                .focused($isFocused)
                .onSubmit(submit)

            if !formattedNumber.isEmpty {
                Text(formattedNumber)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } actions: {
            IntroPrimaryButton(
                title: String(localized: "Next"),
                isBusy: model.isBusy,
                isDisabled: phoneNumber.filter(\.isNumber).count < 5,
                action: submit
            )
            if showsQRCodeOption {
                Button("Log in by QR Code") {
                    Task { await model.requestQRCode() }
                }
                .buttonStyle(.link)
                .disabled(model.isBusy)
            }
        }
        .task {
            await model.loadCountries()
            if phoneNumber.isEmpty, let country = model.detectedCountry {
                select(country)
            }
            isFocused = true
        }
        .task(id: phoneNumber) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let info = await model.phoneNumberInfo(for: phoneNumber)
            if let country = info?.country,
               let code = info?.countryCallingCode,
               matchedCountry?.callingCodes.contains(code) != true {
                // Several countries share calling codes (+1, +7); keep the
                // user's or IP-detected choice unless the code changed.
                matchedCountry = country
            }
            if let info, !info.formattedPhoneNumber.isEmpty {
                formattedNumber = "+\(info.countryCallingCode) \(info.formattedPhoneNumber)"
            } else {
                formattedNumber = ""
            }
        }
    }

    private func select(_ country: CountryInfo) {
        matchedCountry = country
        let code = country.callingCodes.first ?? ""
        let digits = phoneNumber.filter(\.isNumber)
        let rest = model.countries
            .flatMap(\.callingCodes)
            .filter { digits.hasPrefix($0) }
            .max { $0.count < $1.count }
            .map { String(digits.dropFirst($0.count)) } ?? ""
        phoneNumber = "+\(code) \(rest)".trimmingCharacters(in: .whitespaces)
        isFocused = true
    }

    private func submit() {
        Task { await model.submitPhoneNumber(phoneNumber) }
    }
}
