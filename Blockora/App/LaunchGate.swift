import SwiftUI
import UIKit
import AdjustSdk
import FirebaseCore

/// App delegate for the canon launch gate: initializes Adjust, drives APNs push registration
/// (the token is forwarded to launch resolution), and owns the per-screen orientation mask so the
/// main WebView can rotate while the game and every other screen stay portrait.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static private(set) weak var shared: AppDelegate?
    private(set) var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppDelegate.shared = self
        // Firebase Cloud Messaging: the launch route is attributed with the FCM registration
        // token, so Firebase can deliver pushes. Requires GoogleService-Info.plist in the bundle.
        FirebaseApp.configure()
        PushTokenProvider.shared.start()
        if let token = OnlineConfiguration.bundled?.adjustAppToken, !token.isEmpty,
           let config = ADJConfig(appToken: token, environment: ADJEnvironmentProduction) {
            Adjust.initSdk(config)
        }
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        orientationLock
    }

    /// The main WebView is the only screen allowed to rotate; everything else is portrait.
    @MainActor func setWebBrowserActive(_ active: Bool) {
        orientationLock = active
            ? (UIDevice.current.userInterfaceIdiom == .pad ? .all : [.portrait, .landscapeLeft, .landscapeRight])
            : .portrait
        if #available(iOS 16.0, *) {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    /// Forwards the APNs device token to Firebase so it can mint the FCM registration token
    /// (see PushTokenProvider). The launch route is attributed with the FCM token, not APNs.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushTokenProvider.shared.setAPNsToken(deviceToken)
    }
}

/// Branded splash shown while the launch route resolves.
struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.22, blue: 0.36), Color(red: 0.03, green: 0.12, blue: 0.22)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 22) {
                Image("BlockoraLogoBadge")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
            .padding(32)
        }
    }
}

/// The canon launch sequence: Splash → (Adjust + push token) → resolve-player → either the main
/// WebView (web destination) or the game (fallback, the `blocked`/game decision).
struct LaunchGateView: View {
    @ObservedObject var online: PlayerOnlineStore
    @State private var started = false
    @State private var destination: URL?
    @State private var ready = false

    var body: some View {
        Group {
            if !ready {
                SplashView()
            } else if let url = destination, let config = online.config {
                LaunchWebBrowser(url: url, configuration: config)
                    .ignoresSafeArea()
            } else {
                // Fallback: the full Islora game, unchanged and portrait-locked.
                RootView()
                    .preferredColorScheme(.light)
            }
        }
        .task {
            guard !started else { return }; started = true
            try? await Task.sleep(for: .seconds(1))
            // Always resolve the launch route — even without a push token — so the request
            // still reaches the API. The FCM token wait caps at 10s; a missing token
            // (notifications denied, or the simulator) resolves to "" and must not skip it.
            let pushToken = await PushTokenProvider.shared.token(timeout: 10)
            await online.resolveLaunch(pushToken: pushToken)
            destination = online.launch.flatMap { decision in
                online.config.flatMap { decision.destination(using: $0) }
            }
            ready = true
        }
    }
}
