import SwiftUI
import WebKit

/// Live leaderboard rendered by `top-players.html`. The native side hosts the
/// page, answers its data requests through `TopPlayersBridge`, and pushes the
/// local player's stats as they change.
struct TopPlayersView: View {
    let session: GameSession

    /// Set to the deployed page (e.g. `https://isloramodularcity.online/top-players`)
    /// to ship UI updates without an App Store release. nil = bundled copy.
    static let remoteURL: URL? = nil

    @State private var bridge: TopPlayersBridge?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            BlockoraSheetBackground()

            if let bridge, let source = TopPlayersPageSource.resolve() {
                TopPlayersWebView(
                    source: source,
                    bridge: bridge,
                    stats: PlayerStats(session: session),
                    reloadToken: reloadToken,
                    isLoading: $isLoading,
                    loadFailed: $loadFailed
                )
                .opacity(loadFailed ? 0 : 1)
                .accessibilityIdentifier("top-players-web")
            }

            if loadFailed {
                BlockoraPanel {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(BlockoraPalette.coinGold)
                        Text("Leaderboard is offline")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                        Text("Check your connection and try again.")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.75))
                        Button("Retry") {
                            loadFailed = false
                            reloadToken += 1
                        }
                        .buttonStyle(BlockoraGameButtonStyle())
                    }
                }
                .padding(.horizontal, 28)
            } else if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        // No nav title: the page renders its own header, like the other sheets
        // (a title over the clear nav bar was unreadable on the city backdrop).
        .onAppear {
            if bridge == nil { bridge = TopPlayersBridge(session: session) }
        }
    }
}

enum TopPlayersPageSource: Equatable {
    case bundled(URL)
    case remote(URL)

    static func resolve() -> TopPlayersPageSource? {
        if let remote = TopPlayersView.remoteURL { return .remote(remote) }
        return Bundle.main.url(forResource: "top-players", withExtension: "html").map(TopPlayersPageSource.bundled)
    }

    var url: URL {
        switch self {
        case .bundled(let url), .remote(let url): return url
        }
    }
}

/// WKWebView host with the `islora` message handler.
///
/// Native → page: `window.IsloraPlayer` (stats) is set before page scripts
/// run; an `islora:player` event fires when stats change; request results
/// arrive via `window.IsloraBridge.resolve(id, ok, payload)`.
///
/// Page → native: `postMessage({type: "request", id, method, params})`
/// (see `TopPlayersBridge`), plus fire-and-forget `haptic` and `openExternal`.
private struct TopPlayersWebView: UIViewRepresentable {
    let source: TopPlayersPageSource
    let bridge: TopPlayersBridge
    let stats: PlayerStats
    let reloadToken: Int
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: "window.IsloraPlayer = \(Self.json(stats)); window.IsloraNative = { platform: 'ios' };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // Weak proxy: WKUserContentController retains its handlers strongly,
        // which would otherwise leak the coordinator and the web view.
        contentController.add(WeakScriptHandler(context.coordinator), name: "islora")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.lastStats = stats
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.load(source, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.lastReloadToken != reloadToken {
            coordinator.lastReloadToken = reloadToken
            coordinator.load(source, in: webView)
        }

        // The city keeps producing under the sheet; push changes without a reload.
        if coordinator.lastStats != stats {
            coordinator.lastStats = stats
            coordinator.push(stats, to: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "islora")
    }

    static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else { return "null" }
        return string
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: TopPlayersWebView
        var lastStats: PlayerStats?
        var lastReloadToken = 0

        init(parent: TopPlayersWebView) { self.parent = parent }

        func load(_ source: TopPlayersPageSource, in webView: WKWebView) {
            switch source {
            case .bundled(let url): webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            case .remote(let url): webView.load(URLRequest(url: url))
            }
        }

        func push(_ stats: PlayerStats, to webView: WKWebView) {
            let script = """
            window.IsloraPlayer = \(TopPlayersWebView.json(stats));
            window.dispatchEvent(new CustomEvent('islora:player', { detail: window.IsloraPlayer }));
            """
            webView.evaluateJavaScript(script)
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // A 404/500 page is still a "successful" load for WebKit; treat it
            // as offline so the player sees the native retry panel instead.
            if navigationResponse.isForMainFrame,
               let http = navigationResponse.response as? HTTPURLResponse,
               !(200..<400).contains(http.statusCode) {
                decisionHandler(.cancel)
                fail()
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Keep the sheet on the page itself; other http(s) links go to Safari.
            guard let target = navigationAction.request.url,
                  ["http", "https"].contains(target.scheme ?? ""),
                  target.host != parent.source.url.host else {
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(target)
            decisionHandler(.cancel)
        }

        // MARK: Messages

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "request":
                guard let id = body["id"] as? Int, let method = body["method"] as? String, let webView = message.webView else { return }
                let params = body["params"] as? [String: Any] ?? [:]
                Task {
                    do {
                        let payload = try await parent.bridge.handle(method: method, params: params)
                        resolve(id, ok: true, payload: String(data: payload, encoding: .utf8) ?? "null", in: webView)
                    } catch {
                        resolve(id, ok: false, payload: TopPlayersWebView.json(["message": error.localizedDescription]), in: webView)
                    }
                }
            case "haptic":
                switch body["style"] as? String {
                case "success": HapticManager.shared.contractCompleted()
                case "error": HapticManager.shared.actionFailed()
                default: HapticManager.shared.moduleSnap()
                }
            case "openExternal":
                if let string = body["url"] as? String, let url = URL(string: string), url.scheme == "https" {
                    UIApplication.shared.open(url)
                }
            default:
                break
            }
        }

        private func resolve(_ id: Int, ok: Bool, payload: String, in webView: WKWebView) {
            webView.evaluateJavaScript("window.IsloraBridge && window.IsloraBridge.resolve(\(id), \(ok), \(payload));")
        }

        private func fail() {
            parent.isLoading = false
            parent.loadFailed = true
        }
    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
