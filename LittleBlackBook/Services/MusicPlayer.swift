import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class MusicPlayer: NSObject, ObservableObject {
    static let shared = MusicPlayer()

    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .none
    @Published var unsupportedFormatError: String? = nil

    enum RepeatMode: String, CaseIterable {
        case none, one, all
        var icon: String {
            switch self {
            case .none: "repeat"
            case .one:  "repeat.1"
            case .all:  "repeat"
            }
        }
        var isActive: Bool { self != .none }
    }

    private var player: AVAudioPlayer?
    private var queue: [Track] = []
    private var currentIndex: Int = 0
    private var progressTimer: Timer?

    private override init() {
        super.init()
        configureAudioSession()
        setupRemoteControls()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[MusicPlayer] Audio session error:", error)
        }
    }

    // MARK: - Playback

    func play(_ track: Track, queue: [Track] = []) {
        let q = queue.isEmpty ? [track] : queue
        self.queue = q
        self.currentIndex = q.firstIndex(where: { $0.id == track.id }) ?? 0
        loadAndPlay(track)
    }

    func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying { p.pause(); isPlaying = false }
        else         { p.play();  isPlaying = true  }
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if isShuffled {
            currentIndex = Int.random(in: 0..<queue.count)
        } else {
            currentIndex = (currentIndex + 1) % queue.count
        }
        loadAndPlay(queue[currentIndex])
    }

    func previous() {
        if currentTime > 3 { seek(to: 0); return }
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        loadAndPlay(queue[currentIndex])
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
        updateNowPlaying()
    }

    func stop() {
        progressTimer?.invalidate()
        player?.stop()
        player = nil
        isPlaying = false
        currentTrack = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func cycleRepeat() {
        switch repeatMode {
        case .none: repeatMode = .all
        case .all:  repeatMode = .one
        case .one:  repeatMode = .none
        }
    }

    // MARK: - Private

    private func loadAndPlay(_ track: Track) {
        progressTimer?.invalidate()
        player?.stop()

        currentTrack = track

        // Check for known encrypted/unsupported formats before attempting AVAudioPlayer
        let ext = track.fileURL.pathExtension.lowercased()
        let encryptedFormats = ["kgm", "kgma", "vpr", "ncm"]
        if encryptedFormats.contains(ext) {
            unsupportedFormatError = ".\(ext.uppercased()) 是加密格式，暂不支持播放。请使用官方客户端转换后再导入。"
            isPlaying = false
            return
        }

        guard let p = try? AVAudioPlayer(contentsOf: track.fileURL) else {
            unsupportedFormatError = "无法播放该文件（格式不受支持或文件已损坏）"
            isPlaying = false
            print("[MusicPlayer] Cannot load:", track.fileURL)
            return
        }
        p.delegate = self
        p.prepareToPlay()
        p.play()
        player    = p
        isPlaying = true
        duration  = p.duration
        currentTime = 0

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = self?.player?.currentTime ?? 0
            }
        }

        updateNowPlaying()
    }

    // MARK: - Now Playing / Remote Controls

    private func setupRemoteControls() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget  { [weak self] _ in self?.handlePlay();     return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.handlePause();    return .success }
        cc.nextTrackCommand.addTarget     { [weak self] _ in self?.next();   return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: e.positionTime)
            }
            return .success
        }
    }

    private func handlePlay()  { if !isPlaying { togglePlayPause() } }
    private func handlePause() { if isPlaying  { togglePlayPause() } }

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:       track.title,
            MPMediaItemPropertyArtist:      track.artist,
            MPMediaItemPropertyAlbumTitle:  track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration:         duration,
            MPNowPlayingInfoPropertyPlaybackRate:         isPlaying ? 1.0 : 0.0,
        ]
        if let url = track.artworkURL,
           let img = UIImage(contentsOfFile: url.path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - AVAudioPlayerDelegate

extension MusicPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            switch repeatMode {
            case .one:
                loadAndPlay(queue[currentIndex])
            case .all:
                next()
            case .none:
                if currentIndex < queue.count - 1 { next() }
                else { isPlaying = false }
            }
        }
    }
}
