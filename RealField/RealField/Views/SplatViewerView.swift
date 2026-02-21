// SplatViewerView.swift
// RealField
//
// Gaussian Splatをフルスクリーンで表示するビューア
// MetalSplatterライブラリでレンダリングし、
// 仮想ジョイスティック＋ジャイロスコープでFPS風に移動できる

import SwiftUI
import MetalKit
import simd

struct SplatViewerView: View {
    /// 表示する空間データ
    let space: CapturedSpace
    /// Splatファイルの直接URL（ProcessingViewからの遷移用）
    var fileURL: URL?

    @StateObject private var renderer = SplatRendererWrapper()
    @StateObject private var motionService = MotionService()
    @Environment(\.dismiss) private var dismiss

    // ジョイスティック入力
    @State private var moveInput = JoystickOutput.zero
    @State private var lookInput = JoystickOutput.zero

    // カメラ状態
    @State private var cameraPosition = simd_float3(0, 1.0, 0)
    @State private var cameraYaw: Float = 0        // 左右回転
    @State private var cameraPitch: Float = 0      // 上下回転

    // UI状態
    @State private var showControls = true
    @State private var useGyroscope = true
    @State private var showLoadError = false
    @State private var isLoading = true

    /// 移動速度
    private let moveSpeed: Float = 0.03
    /// 視点回転速度
    private let lookSpeed: Float = 0.02

    var body: some View {
        ZStack {
            // Metal描画ビュー
            MetalSplatView(renderer: renderer)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showControls.toggle() }
                }

            // ローディング表示
            if isLoading {
                loadingOverlay
            }

            // コントロールオーバーレイ
            if showControls && !isLoading {
                controlOverlay
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task {
            await loadSplatFile()
        }
        .onAppear {
            if useGyroscope {
                motionService.startUpdates()
            }
            startRenderLoop()
        }
        .onDisappear {
            motionService.stopUpdates()
        }
        .alert("読み込みエラー", isPresented: $showLoadError) {
            Button("閉じる") { dismiss() }
        } message: {
            Text(renderer.errorMessage ?? "ファイルの読み込みに失敗しました")
        }
    }

    // MARK: - ローディングオーバーレイ

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(.cyan)

                Text("3Dシーンを読み込み中...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                if renderer.splatCount > 0 {
                    Text("\(renderer.splatCount) スプラット")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.cyan)
                }
            }
        }
    }

    // MARK: - コントロールオーバーレイ

    private var controlOverlay: some View {
        VStack {
            // 上部ツールバー
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // スプラットカウント
                Text("\(renderer.splatCount) splats")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                // ジャイロスコープ切り替え
                Button {
                    useGyroscope.toggle()
                    if useGyroscope {
                        motionService.recalibrate()
                        motionService.startUpdates()
                    } else {
                        motionService.stopUpdates()
                    }
                } label: {
                    Image(systemName: useGyroscope ? "gyroscope" : "hand.draw")
                        .font(.title3)
                        .foregroundStyle(useGyroscope ? .cyan : .white.opacity(0.5))
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.6), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )

            Spacer()

            // リセットボタン
            HStack {
                Spacer()
                Button {
                    resetCamera()
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.trailing, 20)
            }
            .padding(.bottom, 8)

            // ジョイスティック（下部）
            DualJoystickView(
                moveOutput: $moveInput,
                lookOutput: $lookInput
            )
            .padding(.bottom, 20)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    // MARK: - ファイル読み込み

    /// Splatファイルを読み込む
    private func loadSplatFile() async {
        let url: URL
        if let fileURL {
            url = fileURL
        } else if let splatURL = space.splatFileURL {
            url = splatURL
        } else {
            showLoadError = true
            return
        }

        await renderer.loadFile(at: url)

        if renderer.isLoaded {
            isLoading = false
        } else {
            showLoadError = true
            isLoading = false
        }
    }

    // MARK: - レンダーループ

    /// フレームごとのカメラ更新ループを開始する
    private func startRenderLoop() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                updateCamera()
            }
        }
    }

    /// カメラの位置と回転を更新する
    private func updateCamera() {
        // ジョイスティック入力による視点回転
        if lookInput != .zero {
            cameraYaw += Float(lookInput.x) * lookSpeed
            cameraPitch += Float(lookInput.y) * lookSpeed
            cameraPitch = max(-.pi / 2.5, min(.pi / 2.5, cameraPitch))
        }

        // ジャイロスコープによる視点回転
        if useGyroscope && motionService.isAvailable {
            cameraYaw = motionService.attitude.y
            cameraPitch = -motionService.attitude.x
            cameraPitch = max(-.pi / 2.5, min(.pi / 2.5, cameraPitch))
        }

        // 回転行列を構築
        let yawMatrix = simd_float4x4(rows: [
            simd_float4(cos(cameraYaw), 0, sin(cameraYaw), 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(-sin(cameraYaw), 0, cos(cameraYaw), 0),
            simd_float4(0, 0, 0, 1)
        ])

        let pitchMatrix = simd_float4x4(rows: [
            simd_float4(1, 0, 0, 0),
            simd_float4(0, cos(cameraPitch), -sin(cameraPitch), 0),
            simd_float4(0, sin(cameraPitch), cos(cameraPitch), 0),
            simd_float4(0, 0, 0, 1)
        ])

        let rotation = yawMatrix * pitchMatrix

        // ジョイスティック入力による移動
        if moveInput != .zero {
            let forward = simd_float3(-sin(cameraYaw), 0, -cos(cameraYaw))
            let right = simd_float3(cos(cameraYaw), 0, -sin(cameraYaw))

            cameraPosition += forward * Float(moveInput.y) * moveSpeed
            cameraPosition += right * Float(moveInput.x) * moveSpeed
        }

        // レンダラーにカメラ状態を反映
        renderer.updateCamera(position: cameraPosition, rotation: rotation)
    }

    /// カメラをリセットする
    private func resetCamera() {
        cameraPosition = simd_float3(0, 1.0, 0)
        cameraYaw = 0
        cameraPitch = 0
        motionService.recalibrate()
    }
}

// MARK: - Metal描画ビュー（UIViewRepresentable）

/// MTKViewをSwiftUIに埋め込むラッパー
struct MetalSplatView: UIViewRepresentable {
    let renderer: SplatRendererWrapper

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        renderer.configure(for: mtkView)
        mtkView.delegate = renderer
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

#Preview {
    SplatViewerView(space: CapturedSpace(name: "テスト空間"))
}
