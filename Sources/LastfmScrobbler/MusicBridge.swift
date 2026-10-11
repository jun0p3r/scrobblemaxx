import AppKit
import Foundation

/// Talks to Music.app via AppleScript for things the playerInfo notification doesn't carry
/// (playback position, artwork). Never launches Music: every script is guarded by a running check.
final class MusicBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.fr.LastfmScrobbler.MusicBridge")
    /// Set when the user declined the Automation prompt (error -1743); we then stop asking.
    private(set) var denied = false

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
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 { denied = true }
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
}
