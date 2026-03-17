import Foundation

struct OnlineSong: Identifiable, Sendable, Hashable {
    let id: String          // NetEase song ID (numeric string)
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval  // seconds
    let coverURL: URL?
}
