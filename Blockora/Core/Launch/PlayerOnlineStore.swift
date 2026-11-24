import Foundation
import Combine
import UIKit
import WebKit
import AdjustSdk

@MainActor
final class PlayerOnlineStore: ObservableObject {
    @Published private(set) var launch: LaunchDecision?
    @Published private(set) var players: [TopPlayer] = []
    @Published private(set) var leaderboardMessage: String?
    @Published var syncMessage: String? = nil
    @Published private(set) var isLoading = false
    @Published var playerName: String {
        didSet { defaults.set(playerName, forKey: "online.playerName"); Task { await updateProfile() } }
    }
    let config = OnlineConfiguration.bundled
    private let api: PlayerAPI?
    private let defaults = UserDefaults.standard
    private var appid: String { Bundle.main.bundleIdentifier ?? "" }
    private var identity: String? { UIDevice.current.identifierForVendor?.uuidString }

    init() {
        api = config.map(PlayerAPI.init(config:))
        playerName = defaults.string(forKey: "online.playerName") ?? "Builder \(UUID().uuidString.prefix(4))"
    }

    func resolveLaunch(pushToken: String) async {
        guard let config, let api, let identity,
              var parts = URLComponents(string: config.checkURL) else {
            launch = .temporaryGame; return
        }
        let userAgent = await webViewUserAgent()
        parts.queryItems = [
            URLQueryItem(name: "appid", value: appid),
            URLQueryItem(name: "idfv", value: identity),
            URLQueryItem(name: "deviceName", value: UIDevice.current.name),
            URLQueryItem(name: "pushToken", value: pushToken),
            URLQueryItem(name: "userAgent", value: userAgent),
            URLQueryItem(name: "appVersion", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        ]
        guard let requestURL = parts.url?.absoluteString else { launch = .temporaryGame; return }
        nonisolated struct Request: Encodable, Sendable {
            let appid, ad_id, request_url, name, avatar: String
            let adjust_json: String
            let deeplink = ""
        }
        do {
            guard let token = config.adjustAppToken, !token.isEmpty else {
                throw OnlineError.unavailable
            }
            let attribution = await adjustAttributionJSON()
            let request = Request(appid: appid, ad_id: identity, request_url: requestURL,
                                  name: playerName, avatar: "clover", adjust_json: attribution)
            let response = try await api.call("resolve-player", body: request, as: LaunchDecision.self)
            launch = response.isValid(using: config) ? response : .temporaryGame
        } catch { launch = .temporaryGame }
        await updateProfile()
    }

    /// The device's default WKWebView user agent, forwarded to launch resolution so the
    /// upstream click is attributed with the real browser-engine UA rather than a static name.
    private func webViewUserAgent() async -> String {
        let webView = WKWebView(frame: .zero)
        let value = try? await webView.evaluateJavaScript("navigator.userAgent")
        if let ua = value as? String, !ua.isEmpty { return ua }
        return "Islora"
    }

    /// Best-effort Adjust attribution: wait up to ~10s for it to arrive, then proceed with
    /// an empty object. Missing attribution must never skip launch resolution / the API call.
    private func adjustAttributionJSON() async -> String {
        for attempt in 0..<20 { // up to ~10s, polling every 0.5s
            if let value = await currentAttributionJSON() { return value }
            if attempt < 19 { try? await Task.sleep(for: .milliseconds(500)) }
        }
        return "{}"
    }

    private func currentAttributionJSON() async -> String? {
        await withCheckedContinuation { continuation in
            Adjust.attribution { attribution in
                guard let data = attribution?.jsonResponse, !data.isEmpty,
                      let json = try? JSONSerialization.data(withJSONObject: data),
                      let value = String(data: json, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: value)
            }
        }
    }

    func updateProfile() async {
        guard let api, let identity else { return }
        nonisolated struct Body: Encodable, Sendable { let appid, ad_id, name: String }
        nonisolated struct Ack: Decodable, Sendable { let updated: Bool }
        _ = try? await api.call("player-profile", body: Body(appid: appid, ad_id: identity, name: playerName), as: Ack.self)
    }

    func refreshLeaderboard() async {
        guard !isLoading else { return }
        let cacheKey = "online.leaderboard.\(appid)"
        if players.isEmpty, let data = defaults.data(forKey: cacheKey), let cached = try? JSONDecoder().decode([TopPlayer].self, from: data) { players = cached }
        guard let api else { leaderboardMessage = "Online leaderboard is not configured."; return }
        isLoading = true; defer { isLoading = false }
        do {
            players = try await api.leaderboard(appid: appid)
            defaults.set(try JSONEncoder().encode(players), forKey: cacheKey)
            leaderboardMessage = nil
        } catch { leaderboardMessage = "Offline — showing the last saved leaderboard." }
    }
}
