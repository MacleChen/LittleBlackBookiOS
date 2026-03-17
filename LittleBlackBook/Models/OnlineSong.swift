import Foundation

struct OnlineSong: Identifiable, Sendable, Hashable {
    let id: String          // NetEase song ID
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let coverURL: URL?
    var playURL: URL?       // pre-resolved during search (only present if playable)
}
