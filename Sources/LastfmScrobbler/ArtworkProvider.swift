import AppKit
import CryptoKit
import Foundation

/// Finds album art (Music.app → Last.fm → iTunes Search) and caches it in memory and on disk.
@MainActor
final class ArtworkProvider {
    static let shared = ArtworkProvider()

    private var memory: [String: NSImage] = [:]
    private var misses: Set<String> = []
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LastfmScrobbler/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func key(for track: Track) -> String {
        let artist = (track.albumArtist?.isEmpty == false ? track.albumArtist! : track.artist).lowercased()
        let album = (track.album?.isEmpty == false ? track.album! : track.title).lowercased()
        return artist + "|" + album
    }

    private func fileURL(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name)
    }

    /// Synchronous lookup — memory, then disk. Used by list rows.
    func cached(for track: Track) -> NSImage? {
        let key = Self.key(for: track)
        if let img = memory[key] { return img }
        if let data = try? Data(contentsOf: fileURL(key)), let img = NSImage(data: data) {
            memory[key] = img
            return img
        }
        return nil
    }

    func fetch(for track: Track, musicData: Data?, client: LastfmClient?) async -> NSImage? {
        if let img = cached(for: track) { return img }
        let key = Self.key(for: track)

        if let musicData, let img = store(musicData, key: key) { return img }
        if misses.contains(key) { return nil }

        if let client, let album = track.album, !album.isEmpty,
           let url = try? await client.albumImageURL(artist: track.albumArtist ?? track.artist, album: album),
           let data = try? await download(url), let img = store(data, key: key) {
            return img
        }
        if let url = await iTunesArtworkURL(for: track),
           let data = try? await download(url), let img = store(data, key: key) {
            return img
        }
        misses.insert(key)
        return nil
    }

    private func store(_ data: Data, key: String) -> NSImage? {
        guard let img = NSImage(data: data) else { return nil }
        memory[key] = img
        try? data.write(to: fileURL(key), options: .atomic)
        return img
    }

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private func iTunesArtworkURL(for track: Track) async -> URL? {
        let hasAlbum = track.album?.isEmpty == false
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(hasAlbum ? track.album! : track.title)"),
            URLQueryItem(name: "entity", value: hasAlbum ? "album" : "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = comps.url,
              let data = try? await download(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let small = first["artworkUrl100"] as? String
        else { return nil }
        return URL(string: small.replacingOccurrences(of: "100x100", with: "600x600"))
    }

    /// Average perceived brightness (0 = black, 1 = white), used to decide how much to
    /// darken the blurred background so white text stays readable.
    static func luminance(of image: NSImage) -> Double {
        let side = 16
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return 0.5 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var total = 0.0
        for x in 0..<side {
            for y in 0..<side {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                total += 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
            }
        }
        return total / Double(side * side)
    }
}
