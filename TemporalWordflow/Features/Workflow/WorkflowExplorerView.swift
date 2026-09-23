// The `Workflow ↗` destination.
//
// `/workflows/` is served by the Wordflow API itself and authenticated with the
// same `wordflow_session` cookie as the rest of the app (server.go wires the
// explorer to `authenticatedPlayerID`). Handing the URL to Safari would arrive
// signed out, so the page is opened in-app in a web view seeded from the
// shared cookie jar.

import SwiftUI
import WebKit

struct WorkflowExplorerView: View {
    var link: WorkflowLink
    var onDismiss: () -> Void

    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.offWhite.ignoresSafeArea()
                WorkflowWebView(url: link.url, isLoading: $isLoading)
                if isLoading {
                    LoadingPanel(title: "Opening workflow", subtitle: "Reading durable state…")
                        .padding(Metrics.gutter)
                }
            }
            .navigationTitle(link.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done", action: onDismiss)
                        .font(Typography.sans(16, weight: .heavy))
                }
            }
        }
        .tint(Palette.uv)
    }
}

/// Copies the session cookie into the web view's own store before the first
/// load, then keeps the two jars in step for anything the page sets.
private struct WorkflowWebView {
    var url: URL
    @Binding var isLoading: Bool

    func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        #if os(iOS)
        webView.isOpaque = false
        #endif
        Task { @MainActor in
            await seedCookies(into: webView)
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    @MainActor
    private func seedCookies(into webView: WKWebView) async {
        let jar = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
            await jar.setCookie(cookie)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var isLoading: Bool

        init(isLoading: Binding<Bool>) { _isLoading = isLoading }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            isLoading = false
        }
    }
}

#if os(iOS)
extension WorkflowWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#else
extension WorkflowWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif
