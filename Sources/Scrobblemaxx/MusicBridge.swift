import AppKit
import CoreServices
import Foundation
import os

let log = Logger(subsystem: "com.fr.LastfmScrobbler", category: "music")

/// Talks to Music.app via AppleScript for things the playerInfo notification doesn't carry
/// (playback position, artwork). Never launches Music: every script is guarded by a running check.
final class MusicBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.fr.LastfmScrobbler.MusicBridge")
    /// Set when the user declined the Automation prompt (error -1743); we then stop asking.
    private(set) var denied = false

    enum Access: Equatable {
        case granted, denied, notDetermined, musicNotRunning
    }

    /// Checks (and with `ask`, requests) permission to control Music. `ask` may show the system
    /// prompt and blocks until the user answers, so it runs on the bridge queue.
    func checkAccess(ask: Bool) async -> Access {
        await async { [self] in
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music")
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            switch Int(status) {
            case Int(noErr):
                denied = false
                return .granted
            case errAEEventNotPermitted:
                denied = true
                return .denied
            case errAEEventWouldRequireUserConsent:
                return .notDetermined
            case procNotFound:
                return .musicNotRunning
            default:
                return .notDetermined
            }
        } ?? .notDetermined
    }

    static var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    private func run(_ command: String) -> NSAppleEventDescriptor? {
        guard Self.isMusicRunning, !denied else { return nil }
        let source = """
        if application "Music" is running then
            tell application "Music" to \(command)
        end if
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            log.error("AppleScript \(command, privacy: .public) failed: \(code) \(error[NSAppleScript.errorMessage] as? String ?? "", privacy: .public)")
            if code == -1743 { denied = true }
            return nil
        }
        return result
    }

    private func async<T>(_ work: @escaping () -> T?) async -> T? {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: work()) }
        }
    }

    func playerPosition() async -> Double? {
        await async { [self] in
            guard let d = run("get player position"), d.descriptorType != typeNull else { return nil }
            return d.doubleValue
        }
    }

    func currentArtworkData() async -> Data? {
        await async { [self] in
            guard let d = run("get raw data of artwork 1 of current track") else { return nil }
            let data = d.data
            return data.isEmpty ? nil : data
        }
    }

    struct Snapshot {
        var track: Track?
        var state: PlayerState
        var position: Double
    }

    /// Full current state — used at launch, since Music only notifies on changes.
    func snapshot() async -> Snapshot? {
        await async { [self] in
            guard let list = run("""
                get {player state as string, player position, name of current track, artist of current track, \
                album of current track, album artist of current track, duration of current track, \
                persistent ID of current track}
                """), list.numberOfItems >= 8
            else { return nil }
            func str(_ i: Int) -> String? { list.atIndex(i)?.stringValue }
            let state: PlayerState = switch str(1) {
                case "playing": .playing
                case "paused": .paused
                default: .stopped
            }
            guard let title = str(3), !title.isEmpty, let artist = str(4), !artist.isEmpty else {
                return Snapshot(track: nil, state: state, position: 0)
            }
            // AppleScript gives the persistent ID as hex; the notification gives the same 64 bits as a number.
            let pid = str(8).flatMap { UInt64($0, radix: 16) }.map { String(Int64(bitPattern: $0)) }
            let track = Track(artist: artist, title: title, album: str(5), albumArtist: str(6),
                              duration: list.atIndex(7)?.doubleValue ?? 0, persistentID: pid)
            return Snapshot(track: track, state: state, position: list.atIndex(2)?.doubleValue ?? 0)
        }
    }
}
