import Foundation
import Observation
import AVFoundation
@preconcurrency import Speech

@MainActor protocol CharacterSpeech {
    func speak(_ text: String, softly: Bool)
    func stop()
}
@MainActor @Observable final class SystemCharacterSpeech: NSObject, CharacterSpeech, AVSpeechSynthesizerDelegate {
    static let shared = SystemCharacterSpeech()
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: ObjectIdentifier?
    override init() { super.init(); synthesizer.delegate = self }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { releaseSession(for: ObjectIdentifier(utterance)) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { releaseSession(for: ObjectIdentifier(utterance)) }
    nonisolated private func releaseSession(for id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance == id else { return }
            self.activeUtterance = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    func speak(_ text: String, softly: Bool = false) {
        guard !text.isEmpty else { return }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let utterance = AVSpeechUtterance(string: String(text.prefix(8000)))
            utterance.voice = AVSpeechSynthesisVoice(language: AppLocale.current.language.languageCode?.identifier == "en" ? "en-US" : "zh-CN")
            utterance.rate = softly ? 0.37 : AVSpeechUtteranceDefaultSpeechRate
            utterance.volume = softly ? 0.45 : 0.9
            utterance.pitchMultiplier = softly ? 0.9 : 1
            activeUtterance = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        } catch { /* Text is always available if the device cannot play speech. */ }
    }
    func stop() {
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
enum VoiceError: LocalizedError {
    case permission, unavailable, onDevice, recordingUnavailable
    var errorDescription: String? {
        switch self {
        case .permission: String(localized: "请在系统设置中允许 Lumi 使用麦克风和语音识别。", locale: AppLocale.current)
        case .unavailable: String(localized: "当前无法使用语音识别，请使用文字输入。", locale: AppLocale.current)
        case .onDevice: String(localized: "当前设备或语言尚未准备好本机语音识别，请在系统中下载语言资源，或使用文字输入。", locale: AppLocale.current)
        case .recordingUnavailable: String(localized: "当前没有可用的录音设备，请检查麦克风后重试。", locale: AppLocale.current)
        }
    }
}
struct RecordedVoice: Sendable {
    let data: Data
    let duration: TimeInterval
    let transcript: String
}

/// Owns the audio file on the tap's queue and closes it before the main actor reads it.
private final class AudioRecognitionSink: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest?
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var failed = false
    init(request: SFSpeechAudioBufferRecognitionRequest?, file: AVAudioFile) { self.request = request; self.file = file }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file else { return }
            do { try file.write(from: buffer) } catch { failed = true }
            request?.append(buffer)
        }
    }
    func close() -> TimeInterval {
        lock.withLock {
            let duration = file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            file = nil
            return failed ? 0 : duration
        }
    }
}

@MainActor @Observable final class VoiceInput {
    private(set) var authorized = false
    private(set) var recording = false
    private(set) var finishing = false
    private(set) var transcript = ""
    var error: String?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognizer: SFSpeechRecognizer?
    private var speechAuthorized = false
    private var finalResult = false
    private var tapInstalled = false
    private var run = UUID()
    private var timeout: Task<Void, Never>?
    private var sink: AudioRecognitionSink?
    private var audioURL: URL?
    private var duration: TimeInterval = 0
    func authorize() async {
        let microphone = await AVAudioApplication.requestRecordPermission()
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
        authorized = microphone; speechAuthorized = speech
        error = microphone ? nil : VoiceError.permission.localizedDescription
    }
    func start() {
        guard authorized, !recording, !finishing else { return }
        cancel(); transcript = ""; error = nil; finalResult = false; duration = 0
        do {
            SystemCharacterSpeech.shared.stop()
            // Recording works even when the device has no local transcription resources.
            if speechAuthorized, let recognizer = SFSpeechRecognizer(locale: AppLocale.current), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                self.recognizer = recognizer
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
                self.request = request
            }
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.recordingUnavailable }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("lumi-voice-\(UUID()).m4a")
            audioURL = url
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 64_000], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            let sink = AudioRecognitionSink(request: request, file: file); self.sink = sink
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink.append(buffer) }
            tapInstalled = true
            let identifier = UUID(); run = identifier
            if let request, let recognizer {
                recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, failure in
                    let text = result?.bestTranscription.formattedString
                    let ended = result?.isFinal == true || failure != nil
                    Task { @MainActor [weak self] in
                        guard let self, self.run == identifier else { return }
                        if let text { self.transcript = text }
                        if ended { self.finalResult = true }
                    }
                }
            }
            engine.prepare(); try engine.start(); recording = true
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(55))
                guard !Task.isCancelled else { return }
                self?.stopAudio()
            }
        } catch { cancel(); self.error = error.localizedDescription }
    }
    func finishVoice() async -> RecordedVoice? {
        guard !finishing, recording || audioURL != nil else { return nil }
        finishing = true; stopAudio()
        let identifier = run
        for _ in 0..<15 {
            if finalResult || request == nil { break }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, identifier == run else { return nil }
        }
        guard !Task.isCancelled, identifier == run, let audioURL else { return nil }
        let value: RecordedVoice?
        if duration >= 0.35, let data = try? Data(contentsOf: audioURL), !data.isEmpty {
            value = RecordedVoice(data: data, duration: duration, transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        } else { value = nil }
        cancel()
        if value == nil { error = String(localized: "录音太短，请按住说完后再松开。", locale: AppLocale.current) }
        return value
    }
    func finish() async -> String { await finishVoice()?.transcript ?? "" }
    private func stopAudio() {
        timeout?.cancel(); timeout = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if let sink { duration = sink.close(); self.sink = nil }
        request?.endAudio(); recording = false
    }
    func cancel() {
        run = UUID(); stopAudio(); recognition?.cancel(); recognition = nil; request = nil; recognizer = nil; finishing = false
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }; audioURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor @Observable final class VoicePlayback: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var playing = false
    var error: String?
    func toggle(_ data: Data) {
        if playing { stop(); return }
        do {
            SystemCharacterSpeech.shared.stop()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: data); player?.delegate = self
            guard player?.play() == true else { throw VoiceError.unavailable }
            playing = true; error = nil
        } catch { stop(); self.error = String(localized: "语音播放失败，请重试。", locale: AppLocale.current) }
    }
    func stop() { player?.stop(); player = nil; playing = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identifier else { return }
            self.stop()
        }
    }
}
