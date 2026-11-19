//
//  QRCodeStepView.swift
//  IGram
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// QR code login, like tdesktop's `Intro::QrWidget`. TDLib refreshes the link
/// periodically; each new link produces a new code.
struct QRCodeStepView: View {
    @Bindable var model: IntroModel
    let link: String

    var body: some View {
        IntroStepLayout(
            systemImage: "qrcode.viewfinder",
            title: String(localized: "Log in to Telegram by QR Code"),
            subtitle: "",
            errorMessage: model.errorMessage
        ) {
            Group {
                if let image = QRCodeRenderer.image(for: link) {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .padding(12)
                        .background(.white, in: .rect(cornerRadius: 12))
                } else {
                    ProgressView()
                }
            }
            .frame(width: 220, height: 220)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open Telegram on your phone")
                Text("2. Go to Settings → Devices → Link Desktop Device")
                Text("3. Point your phone at this screen to confirm login")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            Button("Log in by Phone Number") {
                Task { await model.cancelQRCode() }
            }
            .buttonStyle(.link)
            .disabled(model.isBusy)
        }
    }
}

enum QRCodeRenderer {
    /// Renders `string` as a black-on-white QR code.
    static func image(for string: String, scale: CGFloat = 12) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else {
            return nil
        }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
