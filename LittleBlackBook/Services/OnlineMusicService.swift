import Foundation

actor OnlineMusicService {
    static let shared = OnlineMusicService()
    private init() {}

    private let neteaseBase = "https://music.163.com"
    private let huibqBase   = "https://lxmusicapi.onrender.com"
    private let huibqKey    = "share-v3"

    enum Quality: String { case q128 = "128k", q320 = "320k" }

    enum Err: LocalizedError {
        case noResults, noURL, network(String)
        var errorDescription: String? {
            switch self {
            case .noResults:      return "未找到可播放的歌曲（该页结果均为会员专属，请尝试换个关键词）"
            case .noURL:          return "无法获取播放链接"
            case .network(let m): return "网络错误：\(m)"
            }
        }
    }

    // MARK: - Public: search + filter (only returns playable songs)

    func search(query: String, page: Int = 1) async throws -> [OnlineSong] {
        // Fetch 40 candidates so after filtering we still have enough results
        let candidates = try await fetchFromNetease(query: query, page: page, limit: 40)
        guard !candidates.isEmpty else { throw Err.noResults }

        // Concurrently validate URLs via Huibq, preserving original order
        let validated: [OnlineSong] = await withTaskGroup(of: (Int, URL?).self) { group in
            for (idx, song) in candidates.enumerated() {
                group.addTask { [self] in
                    let url = await self.huibqURL(songId: song.id)
                    return (idx, url)
                }
            }
            var pairs: [(Int, URL?)] = []
            for await pair in group { pairs.append(pair) }

            return pairs
                .filter { $0.1 != nil }
                .sorted { $0.0 < $1.0 }
                .prefix(20)
                .map { (idx, url) in
                    var s = candidates[idx]
                    s.playURL = url
                    return s
                }
        }

        guard !validated.isEmpty else { throw Err.noResults }
        return validated
    }

    // MARK: - Download audio to temp file → returns local URL

    func downloadAudio(song: OnlineSong) async throws -> URL {
        // Use the pre-resolved URL from search if available; otherwise re-resolve
        let playURL: URL
        if let cached = song.playURL {
            playURL = cached
        } else {
            guard let resolved = await huibqURL(songId: song.id) else { throw Err.noURL }
            playURL = resolved
        }

        let (tmpFile, _) = try await URLSession.shared.download(from: playURL)
        let pe = playURL.pathExtension.lowercased()
        let ext = ["mp3","flac","m4a","ogg","wav"].contains(pe) ? pe : "mp3"
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tmpFile, to: destURL)
        return destURL
    }

    // MARK: - Private helpers

    /// Fetch raw search results from NetEase (no URL validation).
    private func fetchFromNetease(query: String, page: Int, limit: Int) async throws -> [OnlineSong] {
        var comps = URLComponents(string: "\(neteaseBase)/api/search/get/web")!
        comps.queryItems = [
            .init(name: "s",      value: query),
            .init(name: "type",   value: "1"),
            .init(name: "limit",  value: "\(limit)"),
            .init(name: "offset", value: "\((page - 1) * limit)")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Err.network("HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(NeteaseSearchResp.self, from: data)
        return (decoded.result?.songs ?? []).map(\.asOnlineSong)
    }

    /// Try to resolve a Huibq play URL for the given NetEase song ID.
    /// Returns nil if the song is unavailable (VIP, removed, etc.).
    private func huibqURL(songId: String, quality: Quality = .q128) async -> URL? {
        let urlStr = "\(huibqBase)/url/wy/\(songId)/\(quality.rawValue)"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(huibqKey,           forHTTPHeaderField: "X-Request-Key")
        req.setValue("Mozilla/5.0",      forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8   // short timeout so filtering doesn't take too long

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        struct HResp: Codable { let code: Int; let data: String? }
        guard let hr   = try? JSONDecoder().decode(HResp.self, from: data),
              hr.code == 0,
              let s    = hr.data, !s.isEmpty,
              let play = URL(string: s) else { return nil }
        return play
    }
}

// MARK: - Netease response models

private struct NeteaseSearchResp: Codable {
    let result: NeteaseResult?
    let code: Int
}
private struct NeteaseResult: Codable {
    let songs: [NeteaseSong]?
    let songCount: Int?
}
private struct NeteaseSong: Codable {
    let id: Int
    let name: String
    let artists: [NeteaseArtist]
    let album: NeteaseAlbum
    let duration: Int

    var asOnlineSong: OnlineSong {
        OnlineSong(
            id: String(id),
            title: name,
            artist: artists.map(\.name).joined(separator: " / "),
            album: album.name,
            duration: TimeInterval(duration) / 1000.0,
            coverURL: album.picUrl.flatMap { URL(string: $0) },
            playURL: nil
        )
    }
}
private struct NeteaseArtist: Codable { let id: Int; let name: String }
private struct NeteaseAlbum:  Codable { let id: Int; let name: String; let picUrl: String? }
