import AVFoundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var capture: CaptureController
    @AppStorage("useDarkMode") private var useDarkMode = false

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 440)

            VStack(spacing: 0) {
                preview
                statusBar
            }
            .frame(minWidth: 720)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: capture.selectedVideoDeviceID) { _ in capture.configureSession() }
        .onChange(of: capture.selectedAudioDeviceID) { _ in capture.configureSession() }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                deviceSection
                audioInputSection
                outputSection
                metadataSection
                recordingButtons
            }
            .padding(18)
        }
    }

    private var deviceSection: some View {
        GroupBox("Devices") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Video", selection: $capture.selectedVideoDeviceID) {
                    ForEach(capture.videoDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
                Picker("Audio", selection: $capture.selectedAudioDeviceID) {
                    ForEach(capture.audioDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
                Button("Refresh Devices") {
                    capture.refreshDevices()
                    capture.configureSession()
                }
            }
            .padding(6)
        }
    }

    private var audioInputSection: some View {
        GroupBox("Input Audio") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recording volume")
                    Spacer()
                    Text("\(Int(capture.audioGain * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $capture.audioGain, in: 0...3, step: 0.01)
            }
            .padding(6)
        }
    }

    private var outputSection: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(capture.outputDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose") {
                        chooseOutputDirectory()
                    }
                }
                TextField("Filename template", text: $capture.filenameTemplate)
                Picker("Quality", selection: $capture.metadata.quality) {
                    ForEach(RecordingQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(capture.metadata.quality.plainDescription)
                    Text(capture.metadata.quality.technicalDescription)
                        .font(.system(.caption, design: .monospaced))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }
    }

    private var metadataSection: some View {
        GroupBox("Metadata") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Information added here is embedded into the recorded movie file and also saved in the JSON sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Title", text: $capture.metadata.title)
                TextField("Tape ID", text: $capture.metadata.tapeID)
                DatePicker("Date", selection: $capture.metadata.recordingDate, displayedComponents: .date)
                TextField("People", text: $capture.metadata.people)
                TextField("Place", text: $capture.metadata.place)
                LabeledContent("Source format") {
                    Text(capture.metadata.sourceFormat)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TextField("Notes", text: $capture.metadata.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .padding(6)
        }
    }

    private var recordingButtons: some View {
        HStack(spacing: 12) {
            Button {
                capture.startRecording()
            } label: {
                Label("Record", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(capture.isRecording || !capture.isSessionRunning)

            Button {
                capture.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .disabled(!capture.isRecording)
        }
        .controlSize(.large)
    }

    private var preview: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                CapturePreviewView(session: capture.session)
                    .background(.black)

                HStack(spacing: 12) {
                    Label(capture.isRecording ? "Recording" : "Preview", systemImage: capture.isRecording ? "record.circle.fill" : "play.rectangle")
                        .foregroundStyle(capture.isRecording ? .red : .white)
                    Text(capture.signalText)
                        .foregroundStyle(.white.opacity(0.82))
                    if capture.droppedFrames > 0 {
                        Text("Dropped: \(capture.droppedFrames)")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 6))
                .padding(14)
            }

            AudioMeterView(levels: capture.audioLevels)
                .frame(width: 168)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var statusBar: some View {
        HStack {
            Text(capture.statusText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let last = capture.lastRecording {
                Text(last.url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                useDarkMode.toggle()
            } label: {
                Image(systemName: useDarkMode ? "moon.fill" : "moon")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help(useDarkMode ? "Switch to light mode" : "Switch to dark mode")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = capture.outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            capture.outputDirectory = url
        }
    }
}

private struct AudioMeterView: View {
    let levels: [AudioLevel]

    var body: some View {
        VStack(spacing: 10) {
            if displayLevels.isEmpty {
                Text("Audio Level")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    ForEach(displayLevels) { level in
                        VStack(spacing: 6) {
                            GeometryReader { proxy in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.black.opacity(0.38))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(level.isClipping ? Color.red : meterColor(for: level.rms))
                                        .frame(height: max(3, proxy.size.height * min(1, level.rms * 1.8)))
                                }
                            }
                            .frame(width: 22)

                            Text(label(for: level))
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(level.isClipping ? .red : .secondary)
                                .lineLimit(2)
                                .frame(width: 58)

                            if level.isClipping {
                                Text("CLIP")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var displayLevels: [AudioLevel] {
        Array(levels.prefix(2))
    }

    private func label(for level: AudioLevel) -> String {
        if levels.count == 1 {
            return "Audio\nLevel"
        }
        if levels.count == 2 {
            return level.id == 0 ? "L Audio\nLevel" : "R Audio\nLevel"
        }
        return level.id == 0 ? "L Audio\nLevel" : "R Audio\nLevel"
    }

    private func meterColor(for rms: Double) -> Color {
        if rms > 0.7 { return .orange }
        if rms > 0.35 { return .yellow }
        return .green
    }
}
