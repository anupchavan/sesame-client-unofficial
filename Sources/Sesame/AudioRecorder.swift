import Foundation
import AVFoundation

/// Records voice notes as AAC in an .m4a container (audio/mp4), matching the API contract.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() async -> Bool {
        guard await Self.requestPermission() else { return false }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            guard rec.record() else { return false }
            recorder = rec
            fileURL = url
            isRecording = true
            duration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let rec = self.recorder else { return }
                    rec.updateMeters()
                    self.duration = rec.currentTime
                    self.level = max(0, (rec.averagePower(forChannel: 0) + 50) / 50)
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// Stop and return the recorded file (nil when cancelled).
    func stop(cancelled: Bool = false) -> (url: URL, duration: TimeInterval)? {
        timer?.invalidate(); timer = nil
        let d = duration
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let url = fileURL else { return nil }
        fileURL = nil
        if cancelled || d < 0.4 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, d)
    }
}
