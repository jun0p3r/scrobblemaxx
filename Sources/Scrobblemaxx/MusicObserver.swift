import Foundation

enum PlayerState: String {
    case playing = "Playing", paused = "Paused", stopped = "Stopped"
}

/// Listens to Music.app's distributed notifications. No Automation permission required.
final class MusicObserver {
    var onChange: ((Track?, PlayerState) -> Void)?
    private var token: NSObjectProtocol?

    func start() {
        token = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil, queue: .main
        ) { [weak self] note in
            self?.handle(note.userInfo ?? [:])
        }
    }

    deinit {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
    }

    private func handle(_ info: [AnyHashable: Any]) {
        let state = PlayerState(rawValue: info["Player State"] as? String ?? "") ?? .stopped
        guard let title = info["Name"] as? String, !title.isEmpty,
              let artist = info["Artist"] as? String, !artist.isEmpty
        else {
            onChange?(nil, state)
            return
        }
        let ms = (info["Total Time"] as? NSNumber)?.doubleValue ?? 0
        let pid = (info["PersistentID"] as? NSNumber).map { String($0.int64Value) }
        let track = Track(
            artist: artist,
            title: title,
            album: info["Album"] as? String,
            albumArtist: info["Album Artist"] as? String,
            duration: ms / 1000,
            persistentID: pid
        )
        onChange?(track, state)
    }
}
