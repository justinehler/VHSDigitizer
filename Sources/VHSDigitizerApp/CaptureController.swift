import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

final class CaptureController: NSObject, ObservableObject {
    @Published var videoDevices: [AVCaptureDevice] = []
    @Published var audioDevices: [AVCaptureDevice] = []
    @Published var selectedVideoDeviceID = ""
    @Published var selectedAudioDeviceID = ""
    @Published var metadata = CaptureMetadata()
    @Published var outputDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    @Published var filenameTemplate = "{tape_id}_{title}_{date}_original"
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var audioGain = 1.0
    @Published var statusText = "Waiting for capture permissions."
    @Published var signalText = "No signal yet"
    @Published var audioLevels: [AudioLevel] = []
    @Published var droppedFrames = 0
    @Published var lastRecording: RecordingResult?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "VHSDigitizer.capture.session")
    private let sampleQueue = DispatchQueue(label: "VHSDigitizer.capture.samples")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var activeRecordingURL: URL?
    private var activeSidecarURL: URL?
    private var activeMetadata: CaptureMetadata?
    private var hasStartedWriting = false

    func requestPermissionsAndStart() {
        refreshDevices()

        AVCaptureDevice.requestAccess(for: .video) { [weak self] videoGranted in
            AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                guard let self else { return }
                guard videoGranted else {
                    self.publishStatus("Camera/capture-device access was denied.")
                    return
                }
                if !audioGranted {
                    self.publishStatus("Audio access was denied. Preview can still work, but recording will not include audio.")
                }
                self.configureSession()
            }
        }
    }

    func refreshDevices() {
        let discoveredVideoDevices = Self.discoverVideoDevices()
        let discoveredAudioDevices = Self.discoverAudioDevices()

        DispatchQueue.main.async {
            self.videoDevices = discoveredVideoDevices
            self.audioDevices = discoveredAudioDevices
            if self.selectedVideoDeviceID.isEmpty {
                self.selectedVideoDeviceID = discoveredVideoDevices.first?.uniqueID ?? ""
            }
            if self.selectedAudioDeviceID.isEmpty {
                self.selectedAudioDeviceID = discoveredAudioDevices.first?.uniqueID ?? ""
            }
        }
    }

    func configureSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }

            guard let videoDevice = self.device(with: self.selectedVideoDeviceID, mediaType: .video) else {
                self.session.commitConfiguration()
                self.publishStatus("No video capture device selected.")
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                }
            } catch {
                self.publishStatus("Could not open video device: \(error.localizedDescription)")
            }

            if let audioDevice = self.device(with: self.selectedAudioDeviceID, mediaType: .audio) {
                do {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                    }
                } catch {
                    self.publishStatus("Could not open audio device: \(error.localizedDescription)")
                }
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames = false
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sampleQueue)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            self.audioOutput.setSampleBufferDelegate(self, queue: self.sampleQueue)
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
            }

            self.session.commitConfiguration()
            if !self.session.isRunning {
                self.session.startRunning()
            }

            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
                self.metadata.captureDevice = videoDevice.localizedName
                self.metadata.audioDevice = self.device(with: self.selectedAudioDeviceID, mediaType: .audio)?.localizedName ?? ""
                self.statusText = self.session.isRunning ? "Preview is live." : "Preview did not start."
            }
        }
    }

    func startRecording() {
        sampleQueue.async {
            guard !self.isRecording else { return }

            let metadata = self.currentMetadataSnapshot()
            let baseURL = self.uniqueOutputURL(for: metadata)
            let sidecarURL = baseURL.deletingPathExtension().appendingPathExtension("json")

            do {
                let writer = try AVAssetWriter(outputURL: baseURL, fileType: .mov)
                writer.metadata = MetadataWriter.items(for: metadata)
                writer.shouldOptimizeForNetworkUse = false

                let dimensions = self.currentVideoDimensions()
                let encoderSpecification: [String: Any] = [
                    kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: metadata.quality.prefersHardwareEncoding
                ]
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: Int(dimensions.width),
                    AVVideoHeightKey: Int(dimensions.height),
                    AVVideoEncoderSpecificationKey: encoderSpecification,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: metadata.quality.bitrate,
                        AVVideoExpectedSourceFrameRateKey: 30,
                        AVVideoAllowFrameReorderingKey: false
                    ]
                ]

                let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoInput.expectsMediaDataInRealTime = true
                if writer.canAdd(videoInput) {
                    writer.add(videoInput)
                }

                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: metadata.quality.audioBitrate
                ]
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput.expectsMediaDataInRealTime = true
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                }

                self.writer = writer
                self.videoInput = videoInput
                self.audioInput = audioInput
                self.activeRecordingURL = baseURL
                self.activeSidecarURL = sidecarURL
                self.activeMetadata = metadata
                self.hasStartedWriting = false

                DispatchQueue.main.async {
                    self.isRecording = true
                    self.droppedFrames = 0
                    self.statusText = "Recording to \(baseURL.lastPathComponent)"
                }
            } catch {
                self.publishStatus("Could not start recording: \(error.localizedDescription)")
            }
        }
    }

    func stopRecording(completion: ((RecordingResult?) -> Void)? = nil) {
        sampleQueue.async {
            guard self.isRecording, let writer = self.writer else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            DispatchQueue.main.async {
                self.isRecording = false
                self.statusText = "Finalizing recording..."
            }

            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()

            let url = self.activeRecordingURL
            let sidecarURL = self.activeSidecarURL
            let metadata = self.activeMetadata

            writer.finishWriting {
                var result: RecordingResult?
                if let url, let sidecarURL, let metadata {
                    self.writeSidecar(metadata: metadata, movieURL: url, sidecarURL: sidecarURL)
                    result = RecordingResult(url: url, sidecarURL: sidecarURL, metadata: metadata)
                }

                self.sampleQueue.async {
                    self.writer = nil
                    self.videoInput = nil
                    self.audioInput = nil
                    self.activeRecordingURL = nil
                    self.activeSidecarURL = nil
                    self.activeMetadata = nil
                    self.hasStartedWriting = false
                }

                DispatchQueue.main.async {
                    self.lastRecording = result
                    if let result {
                        self.statusText = "Saved \(result.url.lastPathComponent)"
                    } else {
                        self.statusText = "Recording stopped."
                    }
                    completion?(result)
                }
            }
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        guard isRecording, let writer else { return }

        if !hasStartedWriting {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if writer.startWriting() {
                writer.startSession(atSourceTime: startTime)
                hasStartedWriting = true
            } else {
                publishStatus("Writer failed to start: \(writer.error?.localizedDescription ?? "Unknown error")")
                return
            }
        }

        switch mediaType {
        case .video:
            guard let videoInput, videoInput.isReadyForMoreMediaData else {
                DispatchQueue.main.async { self.droppedFrames += 1 }
                return
            }
            if !videoInput.append(sampleBuffer) {
                publishStatus("Video append failed: \(writer.error?.localizedDescription ?? "Unknown error")")
            }
        case .audio:
            guard hasStartedWriting, let audioInput, audioInput.isReadyForMoreMediaData else { return }
            let adjustedBuffer = AudioLevelMeter.copy(sampleBuffer, applyingGain: audioGain)
            if !audioInput.append(adjustedBuffer) {
                publishStatus("Audio append failed: \(writer.error?.localizedDescription ?? "Unknown error")")
            }
        default:
            break
        }
    }

    private func device(with id: String, mediaType: AVMediaType) -> AVCaptureDevice? {
        let publishedDevices = mediaType == .video ? videoDevices : audioDevices
        let devices = publishedDevices.isEmpty
            ? (mediaType == .video ? Self.discoverVideoDevices() : Self.discoverAudioDevices())
            : publishedDevices
        if let selected = devices.first(where: { $0.uniqueID == id }) {
            return selected
        }
        return devices.first
    }

    private static func discoverVideoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.externalUnknown, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private static func discoverAudioDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.externalUnknown, .builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func currentVideoDimensions() -> CMVideoDimensions {
        if let device = device(with: selectedVideoDeviceID, mediaType: .video) {
            return CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        }
        return CMVideoDimensions(width: 720, height: 480)
    }

    private func currentMetadataSnapshot() -> CaptureMetadata {
        var snapshot = metadata
        snapshot.captureDevice = device(with: selectedVideoDeviceID, mediaType: .video)?.localizedName ?? snapshot.captureDevice
        snapshot.audioDevice = device(with: selectedAudioDeviceID, mediaType: .audio)?.localizedName ?? snapshot.audioDevice
        return snapshot
    }

    private func uniqueOutputURL(for metadata: CaptureMetadata) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: metadata.recordingDate)
        let replacements = [
            "{tape_id}": metadata.tapeID,
            "{title}": metadata.displayTitle,
            "{date}": date
        ]

        var name = filenameTemplate
        for (token, value) in replacements {
            name = name.replacingOccurrences(of: token, with: value)
        }
        name = Filename.sanitized(name.isEmpty ? metadata.displayTitle : name)

        var url = outputDirectory.appendingPathComponent(name).appendingPathExtension("mov")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = outputDirectory.appendingPathComponent("\(name)-\(suffix)").appendingPathExtension("mov")
            suffix += 1
        }
        return url
    }

    private func writeSidecar(metadata: CaptureMetadata, movieURL: URL, sidecarURL: URL) {
        let sidecar = CaptureSidecar(movieFile: movieURL.lastPathComponent, capturedAt: Date(), metadata: metadata)
        do {
            let data = try JSONEncoder.pretty.encode(sidecar)
            try data.write(to: sidecarURL, options: .atomic)
        } catch {
            publishStatus("Saved movie, but sidecar failed: \(error.localizedDescription)")
        }
    }

    private func publishStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }
}

extension CaptureController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            if let description = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                let format = Self.sourceFormatText(dimensions: dimensions, sampleBuffer: sampleBuffer)
                DispatchQueue.main.async {
                    self.signalText = "\(format) HEVC target"
                    self.metadata.sourceFormat = format
                }
            }
            append(sampleBuffer, mediaType: .video)
        } else if output === audioOutput {
            let levels = AudioLevelMeter.levels(from: sampleBuffer)
            if !levels.isEmpty {
                let adjustedLevels = levels.map { level in
                    AudioLevel(
                        id: level.id,
                        rms: min(1, level.rms * self.audioGain),
                        peak: min(1, level.peak * self.audioGain)
                    )
                }
                DispatchQueue.main.async {
                    self.audioLevels = adjustedLevels
                }
            }
            append(sampleBuffer, mediaType: .audio)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            DispatchQueue.main.async { self.droppedFrames += 1 }
        }
    }
}

private extension CaptureController {
    static func sourceFormatText(dimensions: CMVideoDimensions, sampleBuffer: CMSampleBuffer) -> String {
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let frameRate: String
        if duration.isValid, duration.seconds > 0 {
            frameRate = String(format: "%.2f", 1.0 / duration.seconds)
        } else {
            frameRate = "live"
        }
        return "\(dimensions.width)x\(dimensions.height) \(frameRate) fps"
    }
}

private struct CaptureSidecar: Codable {
    let movieFile: String
    let capturedAt: Date
    let metadata: CaptureMetadata
}

private enum Filename {
    static func sanitized(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return value
            .components(separatedBy: invalid).joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
