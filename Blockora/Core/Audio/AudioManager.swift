import AVFoundation

/// Short original bundled sound effects, mixed with the player's own audio.
enum SoundEffect: String {
    case moduleSnap
    case modulePlace
    case synergyDiscovered
    case constructionComplete
    case collapse
    case contractComplete
    case districtUnlock
    case resourceCollect
    case uiTap
}

final class AudioManager {
    static let shared = AudioManager()

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    var isMuted = UserDefaults.standard.bool(forKey: "islora.soundMuted") {
        didSet { UserDefaults.standard.set(isMuted, forKey: "islora.soundMuted") }
    }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    /// Missing audio remains non-fatal.
    func play(_ effect: SoundEffect) {
        guard !isMuted else { return }
        if let cached = players[effect] {
            cached.currentTime = 0
            cached.play()
            return
        }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "caf")
            ?? Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        players[effect] = player
        player.volume = 0.65
        player.play()
    }
}
