import AVFoundation
import MediaPlayer
import Observation
import SwiftUI

/// Reads a reader page aloud. Plays the narration the Mac rendered (Kokoro, synced with the papers) and falls back to
/// the system voice when a page has no audio yet. Reports when a page finished, so the reader can advance.
@Observable
@MainActor
final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    @ObservationIgnored var onFinish: (() -> Void)?
    /// Lock-screen next / previous: +1 or -1 page.
    @ObservationIgnored var onSkip: ((Int) -> Void)?
    @ObservationIgnored private var nowPlaying: [String: Any] = [:]
    @ObservationIgnored private var commandsRegistered = false
    @ObservationIgnored private var artworkCache: [String: MPMediaItemArtwork] = [:]
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var loading: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// `next` is fetched in the background so the following page starts without a gap.
    func play(_ paper: Paper, page: ReaderPage, next: ReaderPage?, folder: PaperFolder) {
        halt()
        isSpeaking = true
        isPaused = false
        registerCommands()
        nowPlaying = [
            MPMediaItemPropertyTitle: paper.title(for: page),
            MPMediaItemPropertyArtist: paper.shortTitle,
            MPMediaItemPropertyAlbumTitle: "PaperDaily",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        if let artwork = artwork(for: paper) { nowPlaying[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let id = paper.id
        let text = paper.spoken(for: page)
        loading = Task { [weak self] in
            let url = await folder.audioFile(id: id, key: page.key)
            guard !Task.isCancelled, let self else { return }
            if let url { self.startPlayer(url) } else { self.speakFallback(text) }
            if let next { _ = await folder.audioFile(id: id, key: next.key) }
        }
    }

    func stop() {
        halt()
        isSpeaking = false
        isPaused = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        setCommands(enabled: false)
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        isPaused = true
        player?.pause()
        synthesizer.pauseSpeaking(at: .immediate)
        publishState()
    }

    func resume() {
        guard isSpeaking, isPaused else { return }
        isPaused = false
        player?.play()
        synthesizer.continueSpeaking()
        publishState()
    }

    /// The paper's generated cover, rendered once per paper for the lock screen.
    private func artwork(for paper: Paper) -> MPMediaItemArtwork? {
        if let cached = artworkCache[paper.id] { return cached }
        let renderer = ImageRenderer(content: CoverView(paper: paper, width: 300))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        artworkCache[paper.id] = artwork
        return artwork
    }

    private func publishState() {
        if let item = player?.currentItem {
            nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime] = item.currentTime().seconds
            let duration = item.duration.seconds
            if duration.isFinite { nowPlaying[MPMediaItemPropertyPlaybackDuration] = duration }
        }
        nowPlaying[MPNowPlayingInfoPropertyPlaybackRate] = isPaused ? 0.0 : 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
    }

    // MARK: Lock screen / Control Center

    private func registerCommands() {
        setCommands(enabled: true)
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPaused == true { self?.resume() } else { self?.pause() } }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.onSkip?(1) }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.onSkip?(-1) }; return .success }
    }

    private func setCommands(enabled: Bool) {
        let c = MPRemoteCommandCenter.shared()
        for command in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.nextTrackCommand, c.previousTrackCommand] {
            command.isEnabled = enabled
        }
    }

    private func halt() {
        loading?.cancel(); loading = nil
        synthesizer.stopSpeaking(at: .immediate)
        player?.pause(); player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func startPlayer(_ url: URL) {
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }
        player = AVPlayer(playerItem: item)
        player?.play()
        Task { [weak self] in
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite {
                self?.nowPlaying[MPMediaItemPropertyPlaybackDuration] = d.seconds
                self?.publishState()
            }
        }
    }

    private func speakFallback(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synthesizer.speak(utterance)
    }

    /// Highest-quality installed English voice (Premium / Enhanced voices are downloaded in Settings > Accessibility > Spoken Content).
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func finished() {
        isSpeaking = false
        onFinish?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
