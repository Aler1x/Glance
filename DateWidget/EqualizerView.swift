//
//  EqualizerView.swift
//  DateWidget
//
//  Created by Alerix and Claude on 09.06.2026.
//

import AppKit
import SwiftUI

struct EqualizerView: View {
    private let barCount = 18
    private let refreshInterval = 1.0 / 15.0
    private let settleDuration = 0.75
    @State private var tap = SystemAudioTap(bandCount: 18)
    @State private var active = false
    @State private var phase = EqualizerPhase.idle
    @State private var settleGeneration = 0
    @State private var startupFailure: SystemAudioTap.StartFailure?

    var body: some View {
        Group {
            if phase.isAnimating {
                TimelineView(.animation(minimumInterval: refreshInterval)) { context in
                    let now = context.date
                    bars(levels: displayLevels(at: now), activity: activity(at: now))
                }
            } else {
                bars(levels: idleLevels, activity: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.tertiary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .overlay {
            if let startupFailure {
                failureOverlay(startupFailure)
            }
        }
        .onAppear {
            startupFailure = nil
            tap.onActive = handleActiveChange
            tap.onFailure = handleFailure
            tap.start()
        }
        .onDisappear {
            tap.onActive = nil
            tap.onFailure = nil
            tap.stop()
        }
    }

    private func bars(levels: [Float], activity: Double) -> some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(barFill(activity: activity))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(index: i, level: levels[i], max: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func barHeight(index: Int, level: Float, max: CGFloat) -> CGFloat {
        let minH = max * 0.08
        return minH + (max - minH) * CGFloat(min(1, Swift.max(0, level)))
    }

    private func handleActiveChange(_ isActive: Bool) {
        startupFailure = nil
        active = isActive
        settleGeneration += 1

        if isActive {
            phase = .live
            return
        }

        let generation = settleGeneration
        phase = .settling(start: Date(), from: normalized(tap.snapshot()))

        DispatchQueue.main.asyncAfter(deadline: .now() + settleDuration) {
            guard generation == settleGeneration, !active else { return }
            phase = .idle
        }
    }

    private func handleFailure(_ failure: SystemAudioTap.StartFailure) {
        active = false
        phase = .idle
        startupFailure = failure
    }

    private func displayLevels(at date: Date) -> [Float] {
        switch phase {
        case .idle:
            return idleLevels
        case .live:
            return normalized(tap.snapshot())
        case let .settling(start, from):
            return interpolate(from: from, to: idleLevels, progress: settleProgress(from: start, to: date))
        }
    }

    private func activity(at date: Date) -> Double {
        switch phase {
        case .idle:
            return 0
        case .live:
            return 1
        case let .settling(start, _):
            return 1 - settleProgress(from: start, to: date)
        }
    }

    private func settleProgress(from start: Date, to date: Date) -> Double {
        let linear = min(1, max(0, date.timeIntervalSince(start) / settleDuration))
        return 1 - pow(1 - linear, 3)
    }

    private func interpolate(from: [Float], to: [Float], progress: Double) -> [Float] {
        zip(from, to).map { start, end in
            start + (end - start) * Float(progress)
        }
    }

    private func normalized(_ levels: [Float]) -> [Float] {
        (0..<barCount).map { i in
            guard i < levels.count else { return idleLevel(at: i) }
            return min(1, Swift.max(0, levels[i]))
        }
    }

    private var idleLevels: [Float] {
        (0..<barCount).map(idleLevel)
    }

    private func idleLevel(at index: Int) -> Float {
        let contour: [Float] = [
            0.13, 0.18, 0.12, 0.22, 0.16, 0.28,
            0.20, 0.15, 0.24, 0.18, 0.30, 0.21,
            0.14, 0.23, 0.17, 0.26, 0.19, 0.12,
        ]
        return contour[index % contour.count]
    }

    private func barFill(activity: Double) -> some ShapeStyle {
        let live = min(1, max(0, activity))
        return LinearGradient(
            colors: [
                .white.opacity(0.34 + 0.18 * live),
                .cyan.opacity(0.22 + 0.23 * live),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func failureOverlay(_ failure: SystemAudioTap.StartFailure) -> some View {
        VStack(spacing: 6) {
            Text("Audio capture blocked")
                .font(.caption.bold())
                .foregroundStyle(.white)
            Text(failure.userMessage)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
            if failure == .permissionDenied {
                Button("Open Settings", action: openAudioPrivacySettings)
                    .font(.caption2)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func openAudioPrivacySettings() {
        let destinations = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security",
        ]

        for destination in destinations {
            guard let url = URL(string: destination) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}

private enum EqualizerPhase: Equatable {
    case idle
    case live
    case settling(start: Date, from: [Float])

    var isAnimating: Bool {
        self != .idle
    }
}
