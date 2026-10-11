import CryptoKit
import Foundation

struct Track: Codable, Equatable {
    var artist: String
    var title: String
    var album: String?
    var albumArtist: String?
    var duration: TimeInterval   // seconds
    var persistentID: String?
}

struct Scrobble: Codable, Equatable {
    var track: Track
    var timestamp: Int           // unix time the track started playing
}

enum LastfmError: Error, LocalizedError {
    case api(code: Int, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .api(let code, let message): return "Last.fm error \(code): \(message)"
        case .badResponse: return "Unexpected response from Last.fm"
        }
    }

    /// Errors worth retrying later (service offline / temporarily unavailable / rate limit).
    var isTransient: Bool {
        if case .api(let code, _) = self { return [8, 11, 16, 29].contains(code) }
        return true
    }

    var isInvalidSession: Bool {
        if case .api(let code, _) = self { return code == 9 }
        return false
    }
}

struct LastfmClient {
    let apiKey: String
    let apiSecret: String

    private static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    /// api_sig = md5(concatenated sorted "keyvalue" pairs + secret). `format` and `callback` are excluded.
    static func signature(for params: [String: String], secret: String) -> String {
        let base = params
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined() + secret
        return Insecure.MD5.hash(data: Data(base.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func call(_ method: String, _ params: [String: String], sessionKey: String? = nil, post: Bool = true) async throws -> [String: Any] {
        var all = params
        all["method"] = method
        all["api_key"] = apiKey
        if let sessionKey { all["sk"] = sessionKey }
        all["api_sig"] = Self.signature(for: all, secret: apiSecret)
        all["format"] = "json"

        var comps = URLComponents()
        comps.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request: URLRequest
        if post {
            request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            // URLComponents leaves '+' and '&' semantics ambiguous for form bodies; encode strictly.
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let body = all.map { k, v in
                "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
            }.joined(separator: "&")
            request.httpBody = Data(body.utf8)
        } else {
            var getComps = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
            getComps.queryItems = comps.queryItems
            request = URLRequest(url: getComps.url!)
        }
        request.setValue("LastfmScrobbler/1.0 (macOS menu bar)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LastfmError.badResponse
        }
        if let code = json["error"] as? Int {
            throw LastfmError.api(code: code, message: json["message"] as? String ?? "")
        }
        return json
    }

    // MARK: Auth (desktop flow)

    func getToken() async throws -> String {
        let json = try await call("auth.getToken", [:], post: false)
        guard let token = json["token"] as? String else { throw LastfmError.badResponse }
        return token
    }

    func authURL(token: String) -> URL {
        URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)")!
    }

    func getSession(token: String) async throws -> (key: String, name: String) {
        let json = try await call("auth.getSession", ["token": token], post: false)
        guard let session = json["session"] as? [String: Any],
              let key = session["key"] as? String,
              let name = session["name"] as? String
        else { throw LastfmError.badResponse }
        return (key, name)
    }

    // MARK: Scrobbling

    func updateNowPlaying(_ track: Track, sessionKey: String) async throws {
        var params = ["artist": track.artist, "track": track.title]
        if let album = track.album, !album.isEmpty { params["album"] = album }
        if let aa = track.albumArtist, !aa.isEmpty { params["albumArtist"] = aa }
        if track.duration > 0 { params["duration"] = String(Int(track.duration)) }
        _ = try await call("track.updateNowPlaying", params, sessionKey: sessionKey)
    }

    /// Scrobbles up to 50 tracks in one request. Returns, per item, whether Last.fm accepted it
    /// (it silently ignores e.g. timestamps older than 14 days).
    @discardableResult
    func scrobble(_ items: [Scrobble], sessionKey: String) async throws -> [Bool] {
        let items = Array(items.prefix(50))
        var params: [String: String] = [:]
        for (i, item) in items.enumerated() {
            params["artist[\(i)]"] = item.track.artist
            params["track[\(i)]"] = item.track.title
            params["timestamp[\(i)]"] = String(item.timestamp)
            if let album = item.track.album, !album.isEmpty { params["album[\(i)]"] = album }
            if let aa = item.track.albumArtist, !aa.isEmpty { params["albumArtist[\(i)]"] = aa }
            if item.track.duration > 0 { params["duration[\(i)]"] = String(Int(item.track.duration)) }
        }
        let json = try await call("track.scrobble", params, sessionKey: sessionKey)

        // "scrobble" is an array for batches but a single object for one item.
        let scrobbles = json["scrobbles"] as? [String: Any]
        let raw = scrobbles?["scrobble"]
        let entries = (raw as? [[String: Any]]) ?? (raw as? [String: Any]).map { [$0] } ?? []
        guard entries.count == items.count else { return items.map { _ in true } }
        return entries.map { entry in
            let ignored = entry["ignoredMessage"] as? [String: Any]
            let code = ignored?["code"].map { "\($0)" } ?? "0"
            return code == "0"
        }
    }

    // MARK: Metadata

    func userImageURL(user: String) async throws -> URL? {
        let json = try await call("user.getInfo", ["user": user], post: false)
        guard let images = (json["user"] as? [String: Any])?["image"] as? [[String: Any]] else { return nil }
        let preferred = images.first { $0["size"] as? String == "large" } ?? images.last
        guard let s = preferred?["#text"] as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    func albumImageURL(artist: String, album: String) async throws -> URL? {
        let json = try await call("album.getInfo", ["artist": artist, "album": album, "autocorrect": "1"], post: false)
        guard let images = (json["album"] as? [String: Any])?["image"] as? [[String: Any]] else { return nil }
        let preferred = images.first { $0["size"] as? String == "mega" }
            ?? images.first { $0["size"] as? String == "extralarge" }
        guard let urlString = preferred?["#text"] as? String, !urlString.isEmpty,
              !urlString.contains("2a96cbd8b46e442fc41c2b86b821562f") // Last.fm's grey star placeholder
        else { return nil }
        return URL(string: urlString)
    }
}
