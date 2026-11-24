import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

/// Reusable Firebase push-token provider. Додай у таргет FirebaseCore + FirebaseMessaging
/// і ВЛАСНИЙ GoogleService-Info.plist проєкту. Жодного app-specific конфігу тут не вшито.
/// Токен видається незалежно від згоди (дозвіл запитується, результат ігнорується,
/// реєстрація безумовна). Очікування токена — максимум 10 с, інакше "".
@MainActor
final class PushTokenProvider: NSObject, MessagingDelegate {
    static let shared = PushTokenProvider()
    private let defaultsKey = "push.fcmToken"
    private var started = false

    /// Викликати один раз одразу після FirebaseApp.configure().
    func start() {
        guard !started else { return }
        started = true
        Messaging.messaging().delegate = self
        Task { @MainActor in
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])   // результат ігноруємо
            UIApplication.shared.registerForRemoteNotifications()           // безумовно
        }
    }

    /// Проброс із AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken.
    func setAPNsToken(_ deviceToken: Data) { Messaging.messaging().apnsToken = deviceToken }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        UserDefaults.standard.set(fcmToken, forKey: defaultsKey)
    }

    /// Чекає до `seconds` (типово 10) на FCM-токен; повертає "" якщо не отримано.
    func token(timeout seconds: Double = 10) async -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1_000_000_000)
        while DispatchTime.now().uptimeNanoseconds < deadline, !Task.isCancelled {
            if let t = UserDefaults.standard.string(forKey: defaultsKey), !t.isEmpty { return t }
            if let t = try? await Messaging.messaging().token(), !t.isEmpty {
                UserDefaults.standard.set(t, forKey: defaultsKey)
                return t
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return ""   // порожній токен при таймауті/невдачі — запуск не блокуємо
    }
}
