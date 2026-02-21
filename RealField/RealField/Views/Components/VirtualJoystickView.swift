// VirtualJoystickView.swift
// RealField
//
// 仮想ジョイスティックコントロール
// Splatビューアでの前後左右移動・上下移動に使用する
// DragGestureで指の位置を追跡し、方向と強度を出力する

import SwiftUI

/// ジョイスティックの出力値
struct JoystickOutput: Equatable {
    /// X軸方向の入力（-1.0〜1.0、右が正）
    var x: CGFloat = 0
    /// Y軸方向の入力（-1.0〜1.0、上が正）
    var y: CGFloat = 0

    static let zero = JoystickOutput()
}

struct VirtualJoystickView: View {
    /// ジョイスティックの出力をバインディングで親に伝える
    @Binding var output: JoystickOutput

    /// ジョイスティックの最大移動半径
    var maxRadius: CGFloat = 50
    /// ジョイスティックのサイズ
    var size: CGFloat = 130

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        ZStack {
            // 外枠（ベース）
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 1.5)
                }

            // 方向インジケーター（十字線）
            Group {
                // 上
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 2, height: 15)
                    .offset(y: -size / 2 + 20)

                // 下
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 2, height: 15)
                    .offset(y: size / 2 - 20)

                // 左
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 15, height: 2)
                    .offset(x: -size / 2 + 20)

                // 右
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 15, height: 2)
                    .offset(x: size / 2 - 20)
            }

            // スティック（動く部分）
            Circle()
                .fill(.white.opacity(isDragging ? 0.4 : 0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isDragging ? 0.6 : 0.3), lineWidth: 2)
                }
                .shadow(color: .white.opacity(isDragging ? 0.15 : 0), radius: 8)
                .offset(dragOffset)
                .animation(.interactiveSpring(response: 0.15), value: dragOffset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let translation = value.translation
                    let distance = sqrt(translation.width * translation.width + translation.height * translation.height)

                    if distance <= maxRadius {
                        dragOffset = translation
                    } else {
                        // 最大半径でクランプ
                        let angle = atan2(translation.height, translation.width)
                        dragOffset = CGSize(
                            width: cos(angle) * maxRadius,
                            height: sin(angle) * maxRadius
                        )
                    }

                    // 正規化した出力を計算（-1〜1）
                    output = JoystickOutput(
                        x: dragOffset.width / maxRadius,
                        y: -dragOffset.height / maxRadius // Y軸反転（上が正）
                    )
                }
                .onEnded { _ in
                    isDragging = false
                    dragOffset = .zero
                    output = .zero
                }
        )
    }
}

// MARK: - デュアルジョイスティック（左：移動、右：視点回転）

/// 左右2つのジョイスティックを配置するコントロールバー
struct DualJoystickView: View {
    @Binding var moveOutput: JoystickOutput
    @Binding var lookOutput: JoystickOutput

    var body: some View {
        HStack {
            // 左ジョイスティック（移動用）
            VStack(spacing: 4) {
                VirtualJoystickView(output: $moveOutput)
                Text("移動")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // 右ジョイスティック（視点回転用）
            VStack(spacing: 4) {
                VirtualJoystickView(output: $lookOutput)
                Text("視点")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 30)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        DualJoystickView(
            moveOutput: .constant(.zero),
            lookOutput: .constant(.zero)
        )
    }
}
