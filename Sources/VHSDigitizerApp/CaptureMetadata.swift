import Foundation

struct CaptureMetadata: Codable, Equatable {
    var title = ""
    var tapeID = ""
    var recordingDate = Date()
    var people = ""
    var place = ""
    var notes = ""
    var sourceFormat = "Waiting for input signal"
    var captureDevice = ""
    var audioDevice = ""
    var codec = "HEVC"
    var quality = RecordingQuality.balancedHardware

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled VHS Capture" : title
    }
}

enum RecordingQuality: String, Codable, CaseIterable, Identifiable {
    case preservationHardware
    case balancedHardware
    case compactHardware
    case preservationSoftware
    case balancedSoftware
    case compactSoftware

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preservationHardware: return "Preservation, Hardware"
        case .balancedHardware: return "Balanced, Hardware"
        case .compactHardware: return "Compact, Hardware"
        case .preservationSoftware: return "Preservation, Software"
        case .balancedSoftware: return "Balanced, Software"
        case .compactSoftware: return "Compact, Software"
        }
    }

    var bitrate: Int {
        switch self {
        case .preservationHardware, .preservationSoftware: return 18_000_000
        case .balancedHardware, .balancedSoftware: return 10_000_000
        case .compactHardware, .compactSoftware: return 5_500_000
        }
    }

    var audioBitrate: Int {
        switch self {
        case .preservationHardware, .preservationSoftware: return 320_000
        case .balancedHardware, .balancedSoftware, .compactHardware, .compactSoftware: return 192_000
        }
    }

    var prefersHardwareEncoding: Bool {
        switch self {
        case .preservationHardware, .balancedHardware, .compactHardware: return true
        case .preservationSoftware, .balancedSoftware, .compactSoftware: return false
        }
    }

    var plainDescription: String {
        switch self {
        case .preservationHardware, .preservationSoftware:
            return "Best choice for tapes you care about most. Larger files, fewer compression artifacts."
        case .balancedHardware, .balancedSoftware:
            return "Good default for family tapes. Keeps quality high without making the files enormous."
        case .compactHardware, .compactSoftware:
            return "Smaller files for casual viewing. Fine detail and tape noise may be softened more."
        }
    }

    var technicalDescription: String {
        let encoder = prefersHardwareEncoding ? "requests VideoToolbox hardware HEVC" : "requests software HEVC"
        return "HEVC/H.265 \(bitrate / 1_000_000) Mbps, \(encoder). Audio is AAC at \(audioBitrate / 1_000) kbps."
    }
}

struct AudioLevel: Identifiable, Equatable {
    let id: Int
    let rms: Double
    let peak: Double

    var isClipping: Bool {
        peak >= 0.98
    }
}

struct RecordingResult: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let sidecarURL: URL
    let metadata: CaptureMetadata
}
