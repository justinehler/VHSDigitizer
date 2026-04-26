import AVFoundation
import Foundation

enum MetadataWriter {
    static func items(for metadata: CaptureMetadata) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        items.append(item(.commonIdentifierTitle, metadata.displayTitle))
        items.append(item(.commonIdentifierDescription, description(for: metadata)))
        items.append(item(.quickTimeMetadataCreationDate, isoDate.string(from: metadata.recordingDate)))
        items.append(item(.quickTimeMetadataDisplayName, metadata.displayTitle))
        return items
    }

    private static func description(for metadata: CaptureMetadata) -> String {
        [
            metadata.tapeID.isEmpty ? nil : "Tape ID: \(metadata.tapeID)",
            metadata.people.isEmpty ? nil : "People: \(metadata.people)",
            metadata.place.isEmpty ? nil : "Place: \(metadata.place)",
            "Source: \(metadata.sourceFormat)",
            metadata.captureDevice.isEmpty ? nil : "Capture device: \(metadata.captureDevice)",
            metadata.audioDevice.isEmpty ? nil : "Audio device: \(metadata.audioDevice)",
            metadata.notes.isEmpty ? nil : metadata.notes
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    private static let isoDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
}
