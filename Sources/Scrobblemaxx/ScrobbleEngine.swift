import AppKit
import Foundation

struct HistoryItem: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case queued, sent, resent, ignored, rejected
    }
    var id = UUID()
    var original: Track          // metadata as Music reported it (used for correction rules)
    var scrobble: Scrobble       // what was / will be sent
    var status: Status

    var date: Date { Date(timeIntervalSince1970: TimeInterval(scrobble.timestamp)) }
}

struct QueuedScrobble: Codable {
    var id: UUID                 // matches a HistoryItem
    var scrobble: Scrobble
}

enum EditTarget: Equatable {
    case current
    case history(UUID)
}

@MainActor
final class ScrobbleEngine: ObservableObject {
    // Auth / settings
    @Published private(set) var credentials = Keychain.load()
    @Published private(set) var pendingToken: String?
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled") }
    }
    /// Fraction of the track that must be played before scrobbling (Last.fm's guideline is ≥ 50%).
    @Published var scrobblePercent: Double = UserDefaults.standard.object(forKey: "scrobblePercent") as? Double ?? 0.5 {
        didSet { UserDefaults.standard.set(scrobblePercent, forKey: "scrobblePercent") }
    }
    /// Also scrobble after 4 minutes of play, whichever comes first (Last.fm's standard rule).
    @Published var capAtFourMinutes: Bool = UserDefaults.standard.object(forKey: "capAtFourMinutes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(capAtFourMinutes, forKey: "capAtFourMinutes") }
    }

    // Playback
    @Published private(set) var currentTrack: Track?      // with corrections applied
    @Published private(set) var playerState: PlayerState = .stopped
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var artwork: NSImage? {
        didSet { artworkLuminance = artwork.map(ArtworkProvider.luminance(of:)) ?? 0 }
    }
    @Published private(set) var artworkLuminance: Double = 0
    @Published private(set) var currentScrobbled = false

    // History / status
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var queue: [QueuedScrobble] = []
    @Published private(set) var status: String = ""
    @Published private(set) var avatar: NSImage?
    /// Whether we may ask Music for position/artwork. When denied, position is only an estimate.
    @Published private(set) var musicAccess: MusicBridge.Access = .notDetermined

    private let observer = MusicObserver()
    private let bridge = MusicBridge()
    private var originalTrack: Track?                     // raw, used for identity
    private var currentOverride: Track?                   // one-off edit of the playing track
    private var currentHistoryID: UUID?
    private var corrections: [String: Track] = [:]

    private var playStartedAt: Date?
    private var accumulated: TimeInterval = 0
    private var trackStartTimestamp = 0
    private var positionAnchor: (value: TimeInterval, at: Date)?
    private var lastPositionSync = Date.distantPast
    private var positionInFlight = false
    private var flushing = false
    private var timers: [Timer] = []

    var client: LastfmClient? {
        credentials.hasAPIKeys ? LastfmClient(apiKey: credentials.apiKey, apiSecret: credentials.apiSecret) : nil
    }

    init() {
        queue = Self.load([QueuedScrobble].self, "queue.json")
            ?? Self.load([Scrobble].self, "queue.json")?.map { QueuedScrobble(id: UUID(), scrobble: $0) }
            ?? []
        history = Self.load([HistoryItem].self, "history.json") ?? []
        corrections = Self.load([String: Track].self, "corrections.json") ?? [:]

        observer.onChange = { [weak self] track, state in
            Task { @MainActor in self?.handle(track: track, state: state) }
        }
        observer.start()
        Task {
            await refreshMusicAccess(ask: true)
            // Music only notifies on changes, so pick up whatever is already playing.
            if let snap = await bridge.snapshot(), originalTrack == nil {
                handle(track: snap.track, state: snap.state, alreadyPlayed: snap.position)
            }
        }

        timers = [
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            },
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.flushQueue() }
            },
        ]
        Task { await flushQueue() }
        loadAvatar()
    }

    private var avatarInFlight = false

    /// Called when the menu opens: retry the avatar if it failed, and notice if the user has
    /// since granted Music access in System Settings.
    func panelOpened() {
        if avatar == nil { loadAvatar() }
        if musicAccess != .granted { Task { await refreshMusicAccess(ask: false) } }
    }

    func refreshMusicAccess(ask: Bool) async {
        let access = await bridge.checkAccess(ask: ask)
        let gained = access == .granted && musicAccess != .granted
        musicAccess = access
        if gained, let t = currentTrack {
            syncPosition()
            if artwork == nil { loadArtwork(for: t) }
        }
    }

    private func loadAvatar() {
        guard let client, let user = credentials.username else { avatar = nil; return }
        guard !avatarInFlight else { return }
        avatarInFlight = true
        Task {
            defer { avatarInFlight = false }
            guard let url = try? await client.userImageURL(user: user),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            avatar = NSImage(data: data)
        }
    }

    // MARK: Playback tracking

    private func sameTrack(_ a: Track?, _ b: Track?) -> Bool {
        guard let a, let b else { return false }
        if let pa = a.persistentID, let pb = b.persistentID { return pa == pb }
        return a.artist == b.artist && a.title == b.title
    }

    private static func correctionKey(_ t: Track) -> String {
        [t.artist, t.title, t.album ?? ""].map { $0.lowercased() }.joined(separator: "|")
    }

    private func corrected(_ raw: Track) -> Track {
        guard let fix = corrections[Self.correctionKey(raw)] else { return raw }
        var t = raw
        t.artist = fix.artist
        t.title = fix.title
        t.album = fix.album
        t.albumArtist = fix.albumArtist
        return t
    }

    /// `alreadyPlayed` is used when we join a track mid-way (app launched while Music was playing).
    private func handle(track raw: Track?, state: PlayerState, alreadyPlayed: TimeInterval = 0) {
        let isNew = !sameTrack(raw, originalTrack)
        if isNew {
            accumulated = alreadyPlayed
            playStartedAt = nil
            currentScrobbled = false
            currentOverride = nil
            currentHistoryID = nil
            positionAnchor = (alreadyPlayed, Date())
            position = alreadyPlayed
            artwork = nil
            trackStartTimestamp = Int(Date().timeIntervalSince1970 - alreadyPlayed)
        }
        originalTrack = raw
        currentTrack = currentOverride ?? raw.map(corrected)

        let wasPlaying = playStartedAt != nil
        playerState = raw == nil ? .stopped : state

        if playerState == .playing {
            if !wasPlaying {
                playStartedAt = Date()
                if let t = currentTrack { sendNowPlaying(t) }
            }
        } else if let start = playStartedAt {
            accumulated += Date().timeIntervalSince(start)
            playStartedAt = nil
        }

        if isNew, let t = currentTrack {
            if musicAccess == .notDetermined || musicAccess == .musicNotRunning {
                Task { await refreshMusicAccess(ask: true) }
            }
            loadArtwork(for: t)
        }
        syncPosition()
        tick()
    }

    private func loadArtwork(for track: Track) {
        if let img = ArtworkProvider.shared.cached(for: track) { artwork = img; return }
        Task {
            let data = await bridge.currentArtworkData()
            let img = await ArtworkProvider.shared.fetch(for: track, musicData: data, client: client)
            if currentTrack.map(ArtworkProvider.key(for:)) == ArtworkProvider.key(for: track) { artwork = img }
        }
    }

    private func playedTime() -> TimeInterval {
        accumulated + (playStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// Asks Music for the real position; between syncs the position is interpolated locally.
    private func syncPosition() {
        guard !positionInFlight, currentTrack != nil else { return }
        positionInFlight = true
        lastPositionSync = Date()
        Task {
            let p = await bridge.playerPosition()
            positionInFlight = false
            positionAnchor = (p ?? playedTime(), Date())
            updatePosition()
        }
    }

    private func updatePosition() {
        guard let anchor = positionAnchor else { position = 0; return }
        let drift = playerState == .playing ? Date().timeIntervalSince(anchor.at) : 0
        let duration = currentTrack?.duration ?? 0
        position = duration > 0 ? min(anchor.value + drift, duration) : anchor.value + drift
    }

    /// Track must be > 30s; scrobble after `scrobblePercent` of its length, or 4 minutes if capped.
    func threshold(for track: Track) -> TimeInterval? {
        guard track.duration > 30 else { return nil }
        let point = track.duration * min(max(scrobblePercent, 0), 1)
        return capAtFourMinutes ? min(point, 240) : point
    }

    /// Where the scrobble point sits on the full-track bar (0...1).
    var thresholdFraction: Double? {
        guard let t = currentTrack, let th = threshold(for: t) else { return nil }
        return th / t.duration
    }

    private func tick() {
        if playerState == .playing, Date().timeIntervalSince(lastPositionSync) > 5 { syncPosition() }
        updatePosition()

        guard let track = currentTrack, let threshold = threshold(for: track),
              playedTime() >= threshold, !currentScrobbled
        else { return }
        currentScrobbled = true
        guard enabled, let raw = originalTrack else { return }

        let item = HistoryItem(original: raw, scrobble: Scrobble(track: track, timestamp: trackStartTimestamp), status: .queued)
        currentHistoryID = item.id
        history.insert(item, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        queue.append(QueuedScrobble(id: item.id, scrobble: item.scrobble))
        save()
        Task { await flushQueue() }
    }

    // MARK: Network

    private func sendNowPlaying(_ track: Track) {
        guard enabled, let client, let sk = credentials.sessionKey else { return }
        Task {
            do { try await client.updateNowPlaying(track, sessionKey: sk) }
            catch { handleError(error) }
        }
    }

    private func setStatus(_ s: HistoryItem.Status, for id: UUID) {
        if let i = history.firstIndex(where: { $0.id == id }) { history[i].status = s }
    }

    func flushQueue() async {
        guard !flushing, !queue.isEmpty, let client, let sk = credentials.sessionKey else { return }
        flushing = true
        defer { flushing = false }

        while !queue.isEmpty {
            let batch = Array(queue.prefix(50))
            do {
                let accepted = try await client.scrobble(batch.map(\.scrobble), sessionKey: sk)
                for (q, ok) in zip(batch, accepted) { setStatus(ok ? .sent : .ignored, for: q.id) }
                queue.removeFirst(batch.count)
                status = ""
                save()
            } catch {
                let transient = (error as? LastfmError)?.isTransient ?? true
                if !transient {
                    // Permanent rejection — drop so the queue doesn't jam.
                    for q in batch { setStatus(.rejected, for: q.id) }
                    queue.removeFirst(batch.count)
                    save()
                }
                handleError(error)
                if transient { return }
            }
        }
    }

    private func handleError(_ error: Error) {
        if let e = error as? LastfmError, e.isInvalidSession {
            credentials.sessionKey = nil
            credentials.username = nil
            Keychain.save(credentials)
            status = "Session expired — please log in again"
        } else {
            status = error.localizedDescription
        }
    }

    // MARK: Editing

    /// The track an edit window should start from, plus whether it has already been sent.
    func editable(_ target: EditTarget) -> (track: Track, alreadySent: Bool)? {
        switch resolve(target) {
        case .current:
            return currentTrack.map { ($0, false) }
        case .history(let id):
            guard let item = history.first(where: { $0.id == id }) else { return nil }
            return (item.scrobble.track, [.sent, .resent].contains(item.status))
        }
    }

    /// Once the playing track has been scrobbled, editing it means editing its history entry.
    private func resolve(_ target: EditTarget) -> EditTarget {
        if target == .current, currentScrobbled, let id = currentHistoryID { return .history(id) }
        return target
    }

    func applyEdit(_ target: EditTarget, artist: String, title: String, album: String, albumArtist: String, remember: Bool) {
        func apply(to t: Track) -> Track {
            var t = t
            t.artist = artist.trimmingCharacters(in: .whitespaces)
            t.title = title.trimmingCharacters(in: .whitespaces)
            t.album = album.trimmingCharacters(in: .whitespaces)
            t.albumArtist = albumArtist.trimmingCharacters(in: .whitespaces)
            return t
        }

        // Keep the now-playing display in sync whichever way the edit is routed.
        if target == .current, let t = currentTrack {
            currentOverride = apply(to: t)
            currentTrack = currentOverride
        }

        switch resolve(target) {
        case .current:
            if remember, let raw = originalTrack { corrections[Self.correctionKey(raw)] = currentTrack }
            if playerState == .playing, let t = currentTrack { sendNowPlaying(t) }

        case .history(let id):
            guard let i = history.firstIndex(where: { $0.id == id }) else { return }
            let fixed = apply(to: history[i].scrobble.track)
            if remember { corrections[Self.correctionKey(history[i].original)] = fixed }
            let wasSent = [.sent, .resent].contains(history[i].status)
            history[i].scrobble.track = fixed

            if let q = queue.firstIndex(where: { $0.id == id }) {
                queue[q].scrobble.track = fixed
            } else if wasSent {
                resend(history[i])
            } else {
                // Ignored/rejected earlier — try again with the corrected metadata.
                history[i].status = .queued
                queue.append(QueuedScrobble(id: id, scrobble: history[i].scrobble))
                Task { await flushQueue() }
            }
        }
        save()
    }

    /// Last.fm's API can't edit or delete scrobbles, so send the corrected one with the
    /// original timestamp and open the library page where the wrong one can be deleted.
    private func resend(_ item: HistoryItem) {
        guard let client, let sk = credentials.sessionKey else {
            status = "Log in to send the corrected scrobble"
            return
        }
        Task {
            do {
                let ok = try await client.scrobble([item.scrobble], sessionKey: sk).first ?? false
                guard ok else {
                    status = "Last.fm ignored the correction (scrobbles older than 14 days can't be resent)"
                    return
                }
                setStatus(.resent, for: item.id)
                save()
                status = "Correction sent — delete the old scrobble on the page that just opened"
                if let url = libraryURL(for: item.date) { NSWorkspace.shared.open(url) }
            } catch { handleError(error) }
        }
    }

    func libraryURL(for date: Date) -> URL? {
        guard let user = credentials.username else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return URL(string: "https://www.last.fm/user/\(user)/library?from=\(f.string(from: date))&rangetype=1day")
    }

    var profileURL: URL? {
        credentials.username.flatMap { URL(string: "https://www.last.fm/user/\($0)") }
    }

    // MARK: Auth

    func saveAPIKeys(key: String, secret: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if key != credentials.apiKey || secret != credentials.apiSecret {
            credentials = Credentials(apiKey: key, apiSecret: secret)
            Keychain.save(credentials)
        }
    }

    func beginLogin() async {
        guard let client else { status = "Enter your API key and secret first"; return }
        do {
            let token = try await client.getToken()
            pendingToken = token
            NSWorkspace.shared.open(client.authURL(token: token))
            status = "Approve access in your browser, then click Finish Login"
        } catch { handleError(error) }
    }

    func finishLogin() async {
        guard let client, let token = pendingToken else { return }
        do {
            let session = try await client.getSession(token: token)
            credentials.sessionKey = session.key
            credentials.username = session.name
            Keychain.save(credentials)
            pendingToken = nil
            status = ""
            loadAvatar()
            await flushQueue()
        } catch { handleError(error) }
    }

    func logout() {
        credentials.sessionKey = nil
        credentials.username = nil
        pendingToken = nil
        avatar = nil
        Keychain.save(credentials)
        status = ""
    }

    // MARK: Persistence

    private static let dataDir: URL = {
        // Folder keeps the pre-rename name so existing history/queue/corrections carry over.
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LastfmScrobbler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: dataDir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: dataDir.appendingPathComponent(name), options: .atomic)
        }
    }

    private func save() {
        Self.write(queue, "queue.json")
        Self.write(history, "history.json")
        Self.write(corrections, "corrections.json")
    }
}
