//
//  EqualizerView.swift
//  DateWidget
//
//  Created by Alerix and Claude on 09.06.2026.
//

import SwiftUI

struct EqualizerView: View {
    private let barCount = 18
    @State private var tap = SystemAudioTap(bandCount: 18)
    @State private var active = false

    var body: some View {
        Group {
            if active {
                // Real-time: read the latest FFT band levels every frame (capped ~30fps).
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                    bars(levels: tap.snapshot())
                }
            } else {
                // No audio playing — keep a quiet contour so the meter still feels intentional.
                bars(levels: nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.tertiary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .onAppear {
            tap.onActive = { active = $0 }
            tap.start()
        }
        .onDisappear {
            tap.onActive = nil
            tap.stop()
        }
    }

    private func bars(levels: [Float]?) -> some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(barFill(levels: levels))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(index: i, level: levels?[i], max: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func barHeight(index: Int, level: Float?, max: CGFloat) -> CGFloat {
        let minH = max * 0.08
        guard let level else {
            return minH + (max - minH) * CGFloat(idleLevel(at: index))
        }
        return minH + (max - minH) * CGFloat(min(1, Swift.max(0, level)))
    }

    private func idleLevel(at index: Int) -> Float {
        let contour: [Float] = [
            0.13, 0.18, 0.12, 0.22, 0.16, 0.28,
            0.20, 0.15, 0.24, 0.18, 0.30, 0.21,
            0.14, 0.23, 0.17, 0.26, 0.19, 0.12,
        ]
        return contour[index % contour.count]
    }

    private func barFill(levels: [Float]?) -> some ShapeStyle {
        LinearGradient(
            colors: [
                .white.opacity(levels == nil ? 0.34 : 0.52),
                .cyan.opacity(levels == nil ? 0.22 : 0.45),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
