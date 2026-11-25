import AppKit
import SwiftUI

extension Array where Element == UInt8 {
    init(hex: String) {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex, let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) {
            out.append(UInt8(hex[i..<j], radix: 16) ?? 0)
            i = j
        }
        self = out
    }
}

/// `EDIFIERBAR_SNAPSHOT=/path/prefix open build/EdifierBar.app` renders the panel with
/// sample data to <prefix>-en.png and <prefix>-hu.png and quits. For checking layout.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        guard let prefix = ProcessInfo.processInfo.environment["EDIFIERBAR_SNAPSHOT"] else { return }
        for lang in AppLanguage.allCases {
            let view = PanelView(speaker: SpeakerController(preview: lang), scrollable: false)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: view)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(prefix)-\(lang.rawValue).png"))
            }
        }
        exit(0)
    }
}
