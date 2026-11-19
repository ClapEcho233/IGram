//
//  FileImage.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Displays an image stored in a TDLib file, downloading it on demand.
///
/// While the file is missing, `placeholder` is shown; a minithumbnail (the
/// tiny blurred preview TDLib embeds in messages) makes a good placeholder.
struct FileImage<Placeholder: View>: View {
    let file: File
    var maxPixelSize = 512
    var priority: FileStore.Priority = .media
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder

    @Environment(TelegramSession.self) private var session
    @State private var image: CGImage?

    var body: some View {
        let item = session.files.item(for: file)
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: item.localURL) {
            guard let url = item.localURL else {
                session.files.download(file, priority: priority)
                return
            }
            image = ImagePipeline.cached(url, maxPixelSize: maxPixelSize)
            if image == nil {
                image = await ImagePipeline.load(url, maxPixelSize: maxPixelSize)
            }
        }
    }
}

/// The blurred inline preview TDLib attaches to photos and videos.
struct MinithumbnailView: View {
    let minithumbnail: Minithumbnail?

    var body: some View {
        if let minithumbnail, let image = ImagePipeline.decode(minithumbnail.data, maxPixelSize: 64) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 6, opaque: true)
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}
