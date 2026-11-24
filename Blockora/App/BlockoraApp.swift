import SwiftUI

@main
struct BlockoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var online = PlayerOnlineStore()

    var body: some Scene {
        WindowGroup {
            // The canon launch gate decides on cold start: the main WebView for a web
            // destination, or the game (RootView) as the fallback.
            LaunchGateView(online: online)
        }
    }
}
