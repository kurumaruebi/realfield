// CaptureGuideView.swift
// RealField
//
// 撮影時の円形プログレスガイドUI
// 角度ベースでキャプチャ済み・未キャプチャのマーカーを表示し、
// 回転方向ガイドでユーザーを誘導する

import SwiftUI

struct CaptureGuideView: View {
    /// 現在の撮影枚数
    let currentCount: Int
    /// 目標撮影枚数
    let targetCount: Int
    /// 現在のデバイスの向き（度数、0〜360）
    let currentHeading: Double
    /// 録画中かどうか
    let isCapturing: Bool
    /// キャプチャ済み角度のインデックスセット
    var capturedIndices: Set<Int> = []
    /// ターゲット角度の配列
    var targetAngles: [Double] = []
    /// 最も近い未キャプチャ角度のインデックス
    var nearestUncapturedIndex: Int? = nil

    /// 進捗率（0.0〜1.0）
    private var progress: Double {
        Double(currentCount) / Double(targetCount)
    }

    /// 各撮影ポイントの角度間隔（度数）- targetAnglesが無い場合のフォールバック
    private var angleStep: Double {
        360.0 / Double(targetCount)
    }

    var body: some View {
        ZStack {
            // 外周の円形トラック
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 4)
                .frame(width: 240, height: 240)

            // 進捗リング
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    .white,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 240, height: 240)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            // 撮影ポイントマーカー
            ForEach(0..<targetCount, id: \.self) { index in
                let angle = markerAngle(for: index)
                let isCaptured = capturedIndices.contains(index)
                let isNext = index == nearestUncapturedIndex

                ZStack {
                    if isCaptured {
                        // キャプチャ済み: 白円 + チェックマーク
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)

                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                    } else if isNext {
                        // 次のターゲット: 白色ハイライト + グロー
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .white.opacity(0.8), radius: 8)
                            .shadow(color: .white.opacity(0.3), radius: 12)
                    } else {
                        // 未キャプチャ: 薄い白
                        Circle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
                .offset(
                    x: 120 * cos(angle * .pi / 180),
                    y: 120 * sin(angle * .pi / 180)
                )
                .animation(.spring(response: 0.3), value: isCaptured)
            }

            // 中央のコンパス針（現在の向き）
            VStack(spacing: 0) {
                Triangle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 16, height: 20)

                Rectangle()
                    .fill(.white.opacity(0.4))
                    .frame(width: 2, height: 80)
            }
            .rotationEffect(.degrees(currentHeading))
            .animation(.easeOut(duration: 0.1), value: currentHeading)

            // 中央の情報表示
            VStack(spacing: 4) {
                if isCapturing {
                    PulsingDot()
                }

                Text("\(currentCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("/ \(targetCount) 枚")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            // 回転方向ガイド矢印（録画中のみ）
            if isCapturing && currentCount < targetCount {
                rotationGuideArrow
            }
        }
        .frame(width: 260, height: 260)
    }

    /// マーカーの角度を計算する（-90で上を0に）
    private func markerAngle(for index: Int) -> Double {
        if !targetAngles.isEmpty, index < targetAngles.count {
            // ターゲット角度を基準に、最初の角度からの相対位置で配置
            let baseAngle = targetAngles[0]
            let relativeAngle = (targetAngles[index] - baseAngle + 360.0)
                .truncatingRemainder(dividingBy: 360.0)
            return relativeAngle - 90.0
        }
        // フォールバック: 等間隔配置
        return Double(index) * angleStep - 90
    }

    /// 回転方向ガイド矢印
    private var rotationGuideArrow: some View {
        VStack {
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                Text("ゆっくり回転")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial.opacity(0.6))
            .clipShape(Capsule())
        }
        .padding(.bottom, -30)
    }
}

// MARK: - 三角形シェイプ

/// 矢印用の三角形
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - パルスドット

/// 撮影中を示すパルスアニメーションドット
struct PulsingDot: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .scaleEffect(scale)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: scale
            )
            .onAppear { scale = 1.4 }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CaptureGuideView(
            currentCount: 7,
            targetCount: 18,
            currentHeading: 140,
            isCapturing: true,
            capturedIndices: [0, 1, 2, 3, 4, 5, 6],
            targetAngles: (0..<18).map { Double($0) * 20.0 },
            nearestUncapturedIndex: 7
        )
    }
}
