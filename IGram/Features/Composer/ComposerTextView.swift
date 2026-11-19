//
//  ComposerTextView.swift
//  IGram
//

import AppKit
import SwiftUI

/// The message input field, backed by `NSTextView` for tdesktop's keyboard
/// behavior: Enter sends, Shift/Option+Enter inserts a line break, ↑ in an
/// empty field edits the last message, Esc cancels a reply or edit, and pasted
/// images or files become attachments.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequest: Int
    var maxHeight: CGFloat = 180
    var onSubmit: () -> Void
    var onEditLast: () -> Bool
    var onCancel: () -> Bool
    var onPasteFiles: ([URL]) -> Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InputTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 2
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.placeholder = placeholder
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        context.coordinator.textView = textView
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? InputTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            context.coordinator.recalculateHeight()
        }
        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
            textView.needsDisplay = true
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: InputTextView?
        var lastFocusRequest: Int

        init(_ parent: ComposerTextView) {
            self.parent = parent
            lastFocusRequest = parent.focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.moveUp(_:)):
                return textView.string.isEmpty && parent.onEditLast()
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onCancel()
            default:
                return false
            }
        }

        func recalculateHeight() {
            guard let textView, let container = textView.textContainer, let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container).height + textView.textContainerInset.height * 2
            let newHeight = min(max(used, 30), parent.maxHeight)
            if abs(newHeight - parent.height) > 0.5 {
                DispatchQueue.main.async { self.parent.height = newHeight }
            }
        }

        func pasteFiles(_ urls: [URL]) -> Bool { parent.onPasteFiles(urls) }
    }

    final class InputTextView: NSTextView {
        weak var coordinator: Coordinator?
        var placeholder = ""

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty, !placeholder.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
            let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
            (placeholder as NSString).draw(at: origin, withAttributes: attributes)
        }

        override func paste(_ sender: Any?) {
            if let urls = Self.pastedFileURLs(), coordinator?.pasteFiles(urls) == true { return }
            super.paste(sender)
        }

        /// Files copied in Finder, or image data written to a temporary file.
        static func pastedFileURLs() -> [URL]? {
            let pasteboard = NSPasteboard.general
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                return urls
            }
            guard pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue]),
                  let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { return nil }
            let url = FileManager.default.temporaryDirectory.appending(path: "Pasted Image \(UUID().uuidString.prefix(8)).png")
            do {
                try png.write(to: url)
                return [url]
            } catch {
                return nil
            }
        }
    }
}
