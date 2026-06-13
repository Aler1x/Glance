//
//  SystemAudioTap.swift
//  DateWidget
//
//  Created by Alerix and Claude on 09.06.2026.
//

import Foundation
import CoreAudio
import Accelerate
import os

/// Captures the system audio output via a Core Audio process tap, runs an FFT on
/// the mixed-down signal, and exposes a smoothed magnitude per frequency band.
///
/// The capture pipeline (tap + private aggregate device + IO proc) is created on
/// `start()` and torn down on `stop()`. Analysis runs on Core Audio's real-time
/// thread; results are try-published without blocking and read by the UI via `snapshot()`.
/// `onActive` fires on the main queue when audible signal starts/stops, so the view
/// can animate only while something is actually playing.
final class SystemAudioTap {
    enum StartFailure: Error, Equatable {
        case permissionDenied
        case noOutputDevice
        case createTap(OSStatus)
        case createAggregate(OSStatus)
        case createIOProc(OSStatus)
        case startDevice(OSStatus)

        var userMessage: String {
            switch self {
            case .permissionDenied:
                return "Allow DateWidget to capture audio in System Settings."
            case .noOutputDevice:
                return "No output device is available for the equalizer."
            case let .createTap(status):
                return "Couldn't create the audio tap (\(Self.describe(status)))."
            case let .createAggregate(status):
                return "Couldn't create the audio device (\(Self.describe(status)))."
            case let .createIOProc(status):
                return "Couldn't attach the audio listener (\(Self.describe(status)))."
            case let .startDevice(status):
                return "Couldn't start audio capture (\(Self.describe(status)))."
            }
        }

        private static func describe(_ status: OSStatus) -> String {
            "\(status) / \(Self.fourCharacterCode(status))"
        }

        private static func fourCharacterCode(_ status: OSStatus) -> String {
            let value = UInt32(bitPattern: status)
            let bytes = [
                UInt8((value >> 24) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff),
            ]
            let scalars = bytes.map { byte -> UnicodeScalar in
                let printable = (32...126).contains(byte) ? byte : UInt8(ascii: ".")
                return UnicodeScalar(printable)
            }
            return String(String.UnicodeScalarView(scalars))
        }
    }

    let bandCount: Int

    /// Called on the main queue when audible signal starts (`true`) or stops (`false`).
    var onActive: ((Bool) -> Void)?
    var onFailure: ((StartFailure) -> Void)?

    // Tunables — adjust to taste if bars sit too low/high.
    private let dbFloor: Float = -55          // magnitude (dB) mapped to a flat bar
    private let gain: Float = 1.4             // overall bar boost
    private let attack: Float = 0.55          // rise smoothing (fast)
    private let decay: Float = 0.12           // fall smoothing (slow, EQ-like ballistics)
    private let signalThreshold: Float = 6e-4 // RMS above which we consider audio "playing"
    private let hangover: Double = 0.35       // seconds of silence tolerated before going idle
    private let analysisRate: Double = 15     // enough motion for the small widget, less CPU churn
    private let maxVisualFrequency: Double = 12_000

    // Core Audio objects
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var running = false
    private var sampleRate: Double = 48_000

    // FFT
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var sampleBuffer: [Float]   // rolling window of the latest `fftSize` samples
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]     // fftSize/2 bins
    private var mixdown: [Float]        // scratch for multi-channel down-mix
    private var bandEdges: [Int]        // bin index boundaries, count = bandCount + 1

    // Published output (read by the main thread). The audio thread only uses a
    // try-lock to publish, so UI snapshots can never block the Core Audio callback.
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var smoothedLevels: [Float]
    private var publishedLevels: [Float]
    private var lastActive = false
    private var silentSamples = Int.max
    private var framesUntilAnalysis = 0
    private var loggedFirstBuffer = false

    init(bandCount: Int = 15, fftSize: Int = 1024) {
        self.bandCount = bandCount
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        sampleBuffer = [Float](repeating: 0, count: fftSize)
        windowed = [Float](repeating: 0, count: fftSize)
        realp = [Float](repeating: 0, count: fftSize / 2)
        imagp = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        mixdown = [Float](repeating: 0, count: 8192)
        smoothedLevels = [Float](repeating: 0, count: bandCount)
        publishedLevels = [Float](repeating: 0, count: bandCount)

        bandEdges = Self.makeBandEdges(
            bandCount: bandCount,
            fftSize: fftSize,
            sampleRate: sampleRate,
            maxFrequency: maxVisualFrequency
        )

        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        teardown()
        vDSP_destroy_fftsetup(fftSetup)
        lock.deallocate()
    }

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        guard !running else { return true }

        switch startCapture() {
        case .success:
            running = true
            return true
        case let .failure(failure):
            NSLog("SystemAudioTap: \(failure.userMessage)")
            teardown()
            DispatchQueue.main.async { [onFailure] in onFailure?(failure) }
            return false
        }
    }

    func stop() {
        guard running || tapID != kAudioObjectUnknown else { return }
        teardown()
        running = false
        if lastActive { lastActive = false; onActive?(false) }
    }

    func snapshot() -> [Float] {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return publishedLevels
    }

    // MARK: Capture setup

    private func startCapture() -> Result<Void, StartFailure> {
        guard let outputUID = Self.defaultOutputDeviceUID() else { return .failure(.noOutputDevice) }

        let desc = CATapDescription(__excludingProcesses: [], andDeviceUID: outputUID, withStream: 0)
        desc.name = "DateWidget EQ Tap"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTap)
        guard tapStatus == noErr, newTap != kAudioObjectUnknown else {
            return .failure(tapStatus == kAudioDevicePermissionsError ? .permissionDenied : .createTap(tapStatus))
        }
        tapID = newTap
        readTapFormat()

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "DateWidget EQ Tap",
            kAudioAggregateDeviceUIDKey as String: "dev.Alerix.DateWidget.eqtap",
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: desc.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey as String: true,
                ]
            ],
        ]

        var agg = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg)
        guard aggregateStatus == noErr, agg != kAudioObjectUnknown else {
            return .failure(aggregateStatus == kAudioDevicePermissionsError ? .permissionDenied : .createAggregate(aggregateStatus))
        }
        aggregateID = agg

        let block: AudioDeviceIOBlock = { [weak self] _, inInputData, _, _, _ in
            self?.process(inInputData)
        }
        var proc: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, nil, block)
        guard ioProcStatus == noErr, let proc else {
            return .failure(ioProcStatus == kAudioDevicePermissionsError ? .permissionDenied : .createIOProc(ioProcStatus))
        }
        ioProcID = proc

        let startStatus = AudioDeviceStart(aggregateID, proc)
        guard startStatus == noErr else {
            return .failure(startStatus == kAudioDevicePermissionsError ? .permissionDenied : .startDevice(startStatus))
        }
        NSLog("SystemAudioTap: started (sampleRate=\(sampleRate))")
        return .success(())
    }

    private func teardown() {
        if let proc = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        os_unfair_lock_lock(lock)
        for i in publishedLevels.indices { publishedLevels[i] = 0 }
        os_unfair_lock_unlock(lock)
        for i in smoothedLevels.indices { smoothedLevels[i] = 0 }
        silentSamples = Int.max
        framesUntilAnalysis = 0
    }

    private func readTapFormat() {
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd) == noErr, asbd.mSampleRate > 0 {
            sampleRate = asbd.mSampleRate
            NSLog("SystemAudioTap: format sampleRate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame) formatID=\(asbd.mFormatID) flags=\(asbd.mFormatFlags) bytesPerFrame=\(asbd.mBytesPerFrame)")
            bandEdges = Self.makeBandEdges(
                bandCount: bandCount,
                fftSize: fftSize,
                sampleRate: sampleRate,
                maxFrequency: maxVisualFrequency
            )
        }
    }

    private static func makeBandEdges(
        bandCount: Int,
        fftSize: Int,
        sampleRate: Double,
        maxFrequency: Double
    ) -> [Int] {
        let nyquist = sampleRate / 2
        let binHz = sampleRate / Double(fftSize)
        let minBin = max(1, Int((60 / binHz).rounded()))
        let maxBin = min(fftSize / 2, max(minBin + bandCount, Int((min(maxFrequency, nyquist * 0.9) / binHz).rounded())))

        return (0...bandCount).map { b in
            Int((Double(minBin) * pow(Double(maxBin) / Double(minBin), Double(b) / Double(bandCount))).rounded())
        }
    }

    private static func defaultOutputDeviceUID() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }

        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &uidAddr, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    // MARK: Audio-thread processing

    private func process(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let first = buffers.first else { return }

        let frames = buffers.reduce(Int.max) { partial, buffer in
            guard buffer.mData != nil else { return partial }
            let channels = max(1, Int(buffer.mNumberChannels))
            let bufferFrames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            return min(partial, bufferFrames)
        }
        guard frames > 0 else { return }

        if !loggedFirstBuffer {
            loggedFirstBuffer = true
            var peak: Float = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let channels = max(1, Int(buffer.mNumberChannels))
                let raw = data.assumingMemoryBound(to: Float.self)
                var bufferPeak: Float = 0
                vDSP_maxmgv(raw, 1, &bufferPeak, vDSP_Length(frames * channels))
                peak = max(peak, bufferPeak)
            }
            NSLog("SystemAudioTap: first buffer buffers=\(buffers.count) channels=\(Int(first.mNumberChannels)) frames=\(frames) peak=\(peak)")
        }

        let n = min(frames, mixdown.count)
        for frame in 0..<n {
            var sum: Float = 0
            var channelCount = 0

            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let channels = max(1, Int(buffer.mNumberChannels))
                let raw = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<channels {
                    sum += raw[frame * channels + channel]
                }
                channelCount += channels
            }

            mixdown[frame] = channelCount > 0 ? sum / Float(channelCount) : 0
        }
        mixdown.withUnsafeBufferPointer { appendToWindow($0.baseAddress!, count: n) }

        let audible = updateActivity(frames: frames)
        guard lastActive else { return }
        guard audible else { return }
        framesUntilAnalysis -= frames
        guard framesUntilAnalysis <= 0 else { return }
        framesUntilAnalysis += max(1, Int(sampleRate / analysisRate))
        computeFFT()
    }

    private func appendToWindow(_ samples: UnsafePointer<Float>, count: Int) {
        if count >= fftSize {
            for i in 0..<fftSize { sampleBuffer[i] = samples[count - fftSize + i] }
        } else {
            let keep = fftSize - count
            for i in 0..<keep { sampleBuffer[i] = sampleBuffer[i + count] }
            for i in 0..<count { sampleBuffer[keep + i] = samples[i] }
        }
    }

    private func updateActivity(frames: Int) -> Bool {
        var rms: Float = 0
        vDSP_rmsqv(sampleBuffer, 1, &rms, vDSP_Length(fftSize))
        let audible = rms > signalThreshold
        if audible {
            silentSamples = 0
        } else if silentSamples < Int.max - frames {
            silentSamples += frames
        }
        let active = Double(silentSamples) < sampleRate * hangover
        if active != lastActive {
            if active { framesUntilAnalysis = 0 }
            lastActive = active
            let callback = onActive
            DispatchQueue.main.async { callback?(active) }
        }
        return audible
    }

    private func computeFFT() {
        vDSP_vmul(sampleBuffer, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    let complex = raw.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complex.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { mp in
                    vDSP_zvabs(&split, 1, mp.baseAddress!, 1, vDSP_Length(fftSize / 2))
                }
            }
        }
        storeBands()
    }

    private func storeBands() {
        let denom = Float(fftSize / 2)
        for b in 0..<bandCount {
            let lo = bandEdges[b]
            let hi = max(lo + 1, bandEdges[b + 1])
            var peak: Float = 0
            for bin in lo..<hi where bin < magnitudes.count { peak = max(peak, magnitudes[bin]) }

            let db = 20 * log10(peak / denom + 1e-7)
            var target = (db - dbFloor) / (0 - dbFloor) * gain
            target = min(1, max(0, target))

            let current = smoothedLevels[b]
            smoothedLevels[b] = current + (target - current) * (target > current ? attack : decay)
        }

        if os_unfair_lock_trylock(lock) {
            publishedLevels = smoothedLevels
            os_unfair_lock_unlock(lock)
        }
    }
}
