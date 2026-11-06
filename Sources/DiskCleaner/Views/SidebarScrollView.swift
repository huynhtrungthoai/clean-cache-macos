import SwiftUI
import AppKit

/// A native viewport keeps sidebar drawing, tracking areas and clicks in the
/// same coordinates, including underneath the unified window toolbar.
struct SidebarScrollView<Content: View>: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()

        let host = NSHostingView(rootView: AnyView(content.environment(\.isEnabled, isEnabled)))
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            host.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            host.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(content.environment(\.isEnabled, isEnabled))
    }
}
