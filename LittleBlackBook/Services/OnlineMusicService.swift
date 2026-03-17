import Foundation

actor OnlineMusicService {
    static let shared = OnlineMusicService()
    private init() {}

    // NetEase Music public web API
    private let neteaseBase = "https://music.163.com"
    // Huibq URL resolver (fallback)
    private let huibqBase   = "https://lxmusicapi.onrender.com"
    private let huibqKey    = "share-v3"

    enum Quality: String { case q128 = "128k", q320 = "320k" }

    enum Err: LocalizedError {
        case noResults, noURL, network(String)
        var errorDescription: String? {
            switch self {
            case .noResults:      return "未找到相关歌曲"
            case .noURL:          return "无法获取播放链接（该歌曲可能为会员专属）"
            case .network(let m): return "网络错误：\(m)"
            }
        }
    }

    // MARK: - Search

    func search(query: String, page: Int = 1, limit: Int = 20) async throws -> [OnlineSong] {
        var comps = URLComponents(string: "\(neteaseBase)/api/search/get/web")!
        comps.queryItems = [
            .init(name: "s",      value: query),
            .init(name: "type",   value: "1"),
            .init(name: "limit",  value: "\(limit)"),
            .init(name: "offset", value: "\((page - 1) * limit)")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Err.network("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(NeteaseSearchResp.self, from: data)
        let songs = decoded.result?.songs ?? []
        if songs.isEmpty { throw Err.noResults }
        return songs.map(\.asOnlineSong)
    }

    // MARK: - Resolve play URL

    func resolvePlayURL(song: OnlineSong, quality: Quality = .q128) async throws -> URL {
        // Primary: NetEase outer URL (free songs, no auth)
        let outerStr = "\(neteaseBase)/song/media/outer/url?id=\(song.id).mp3"
        if let outerURL = URL(string: outerStr) {
            let config = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: config)
            if let (_, res) = try? await session.data(from: outerURL),
               let http = res as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                return outerURL
            }
        }

        // Fallback: Huibq resolver
        let urlStr = "\(huibqBase)/url/wy/\(song.id)/\(quality.rawValue)"
        guard let url = URL(string: urlStr) else { throw Err.noURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(huibqKey,           forHTTPHeaderField: "X-Request-Key")
        req.setValue("Mozilla/5.0",      forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, _) = try await URLSession.shared.data(for: req)
        struct HResp: Codable { let code: Int; let data: String? }
        let hr = try JSONDecoder().decode(HResp.self, from: data)
        guard hr.code == 0, let s = hr.data, let playURL = URL(string: s) else { throw Err.noURL }
        return playURL
    }

    // MARK: - Download audio to temp file → returns local URL

    func downloadAudio(song: OnlineSong) async throws -> URL {
        let playURL = try await resolvePlayURL(song: song)
        let (tmpFile, _) = try await URLSession.shared.download(from: playURL)
        let ext = playURL.pathExtension.isEmpty ? "mp3" : playURL.pathExtension
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tmpFile, to: destURL)
        return destURL
    }
}

// MARK: - Netease response models (private)

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
    let duration: Int   // milliseconds

    var asOnlineSong: OnlineSong {
        OnlineSong(
            id: String(id),
            title: name,
            artist: artists.map(\.name).joined(separator: " / "),
            album: album.name,
            duration: TimeInterval(duration) / 1000.0,
            coverURL: album.picUrl.flatMap { URL(string: $0) }
        )
    }
}

private struct NeteaseArtist: Codable { let id: Int; let name: String }
private struct NeteaseAlbum:  Codable { let id: Int; let name: String; let picUrl: String? }
