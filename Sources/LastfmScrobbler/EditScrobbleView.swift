import SwiftUI

struct EditScrobbleView: View {
    @EnvironmentObject var engine: ScrobbleEngine
    let target: EditTarget
    let alreadySent: Bool

    @State var artist: String
    @State var title: String
    @State var album: String
    @State var albumArtist: String
    @State private var remember = false

    init(target: EditTarget, track: Track, alreadySent: Bool) {
        self.target = target
        self.alreadySent = alreadySent
        _artist = State(initialValue: track.artist)
        _title = State(initialValue: track.title)
        _album = State(initialValue: track.album ?? "")
        _albumArtist = State(initialValue: track.albumArtist ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("Title", text: $title)
                TextField("Artist", text: $artist)
                TextField("Album", text: $album)
                TextField("Album artist", text: $albumArtist)
            }

            Toggle("Always apply this correction to this track", isOn: $remember)

            if alreadySent {
                Label("This was already sent. Last.fm can't edit scrobbles through its API, so a corrected one will be sent and your library will open so you can delete the old one.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { AuxWindow.close("edit") }
                    .keyboardShortcut(.cancelAction)
                Button(alreadySent ? "Send Correction" : "Save") {
                    engine.applyEdit(target, artist: artist, title: title, album: album,
                                     albumArtist: albumArtist, remember: remember)
                    AuxWindow.close("edit")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(artist.trimmingCharacters(in: .whitespaces).isEmpty
                          || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
