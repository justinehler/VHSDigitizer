import AVFoundation
import CoreMedia
import Foundation

enum AudioLevelMeter {
    static func copy(_ sampleBuffer: CMSampleBuffer, applyingGain gain: Double) -> CMSampleBuffer {
        guard abs(gain - 1.0) > 0.001 else {
            return sampleBuffer
        }

        var copiedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopy(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleBufferOut: &copiedBuffer
        )
        guard copyStatus == noErr, let copiedBuffer else {
            return sampleBuffer
        }

        applyGain(gain, to: copiedBuffer)
        return copiedBuffer
    }

    static func levels(from sampleBuffer: CMSampleBuffer) -> [AudioLevel] {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return []
        }

        let asbd = streamDescription.pointee
        let channelCount = max(1, Int(asbd.mChannelsPerFrame))
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isNonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bitsPerChannel = Int(asbd.mBitsPerChannel)

        var bufferListSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr, bufferListSize > 0 else { return [] }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.assumingMemoryBound(to: AudioBufferList.self)
        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return [] }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard !buffers.isEmpty else { return [] }

        if isNonInterleaved || buffers.count == channelCount {
            return channelLevelsFromPlanarBuffers(buffers, channelCount: channelCount, isFloat: isFloat, bitsPerChannel: bitsPerChannel)
        }

        return channelLevelsFromInterleavedBuffer(
            buffers[0],
            channelCount: channelCount,
            isFloat: isFloat,
            bitsPerChannel: bitsPerChannel
        )
    }

    private static func applyGain(_ gain: Double, to sampleBuffer: CMSampleBuffer) {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return
        }

        let asbd = streamDescription.pointee
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bitsPerChannel = Int(asbd.mBitsPerChannel)

        var bufferListSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr, bufferListSize > 0 else { return }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.assumingMemoryBound(to: AudioBufferList.self)
        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            if isFloat, bitsPerChannel == 32 {
                let pointer = data.assumingMemoryBound(to: Float.self)
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                scale(pointer: pointer, sampleCount: sampleCount, gain: gain)
            } else if bitsPerChannel == 16 {
                let pointer = data.assumingMemoryBound(to: Int16.self)
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                scale(pointer: pointer, sampleCount: sampleCount, gain: gain)
            }
        }
    }

    private static func scale(pointer: UnsafeMutablePointer<Float>, sampleCount: Int, gain: Double) {
        for index in 0..<sampleCount {
            let scaled = max(-1.0, min(1.0, Double(pointer[index]) * gain))
            pointer[index] = Float(scaled)
        }
    }

    private static func scale(pointer: UnsafeMutablePointer<Int16>, sampleCount: Int, gain: Double) {
        for index in 0..<sampleCount {
            let scaled = Double(pointer[index]) * gain
            let clipped = max(Double(Int16.min), min(Double(Int16.max), scaled))
            pointer[index] = Int16(clipped)
        }
    }

    private static func channelLevelsFromPlanarBuffers(
        _ buffers: UnsafeMutableAudioBufferListPointer,
        channelCount: Int,
        isFloat: Bool,
        bitsPerChannel: Int
    ) -> [AudioLevel] {
        (0..<min(channelCount, buffers.count)).map { channel in
            level(from: buffers[channel], channelIndex: channel, channelCount: 1, isFloat: isFloat, bitsPerChannel: bitsPerChannel)
        }
    }

    private static func channelLevelsFromInterleavedBuffer(
        _ buffer: AudioBuffer,
        channelCount: Int,
        isFloat: Bool,
        bitsPerChannel: Int
    ) -> [AudioLevel] {
        (0..<channelCount).map { channel in
            level(from: buffer, channelIndex: channel, channelCount: channelCount, isFloat: isFloat, bitsPerChannel: bitsPerChannel)
        }
    }

    private static func level(
        from buffer: AudioBuffer,
        channelIndex: Int,
        channelCount: Int,
        isFloat: Bool,
        bitsPerChannel: Int
    ) -> AudioLevel {
        guard let data = buffer.mData else {
            return AudioLevel(id: channelIndex, rms: 0, peak: 0)
        }

        if isFloat, bitsPerChannel == 32 {
            let pointer = data.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            return computeLevel(pointer: pointer, sampleCount: sampleCount, channelIndex: channelIndex, channelCount: channelCount)
        }

        if bitsPerChannel == 16 {
            let pointer = data.assumingMemoryBound(to: Int16.self)
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
            return computeLevel(pointer: pointer, sampleCount: sampleCount, channelIndex: channelIndex, channelCount: channelCount)
        }

        return AudioLevel(id: channelIndex, rms: 0, peak: 0)
    }

    private static func computeLevel(pointer: UnsafePointer<Float>, sampleCount: Int, channelIndex: Int, channelCount: Int) -> AudioLevel {
        var sumSquares = 0.0
        var peak = 0.0
        var count = 0

        var index = channelIndex
        while index < sampleCount {
            let value = min(1.0, abs(Double(pointer[index])))
            sumSquares += value * value
            peak = max(peak, value)
            count += 1
            index += channelCount
        }

        let rms = count > 0 ? sqrt(sumSquares / Double(count)) : 0
        return AudioLevel(id: channelIndex, rms: rms, peak: peak)
    }

    private static func computeLevel(pointer: UnsafePointer<Int16>, sampleCount: Int, channelIndex: Int, channelCount: Int) -> AudioLevel {
        var sumSquares = 0.0
        var peak = 0.0
        var count = 0

        var index = channelIndex
        while index < sampleCount {
            let value = min(1.0, abs(Double(pointer[index])) / Double(Int16.max))
            sumSquares += value * value
            peak = max(peak, value)
            count += 1
            index += channelCount
        }

        let rms = count > 0 ? sqrt(sumSquares / Double(count)) : 0
        return AudioLevel(id: channelIndex, rms: rms, peak: peak)
    }
}
