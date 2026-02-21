// CaptureView.swift
// RealField
//
// カメラを使った空間キャプチャ画面
// 録画ボタンを押してゆっくり回転するだけで
// 角度ベースで自動的にフレームをキャプチャする

import SwiftUI
import AVFoundation

struct CaptureView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var cameraService = CameraService()
    @Environment(\.dismiss) private var dismiss

    @State private var isRecording = false
    @State private var showProcessing = false
    @State private var capturedSpace: CapturedSpace?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // カメラプレビュー
            CameraPreviewView(session: cameraService.session)
                .ignoresSafeArea()

            // オーバーレイUI
            VStack {
                // ヘッダー（閉じるボタン＋撮影枚数）
                headerView
                    .padding(.top, 8)

                Spacer()

                // 撮影ガイド（円形プログレス）
                CaptureGuideView(
                    currentCount: cameraService.photoCount,
                    targetCount: cameraService.targetPhotoCount,
                    currentHeading: cameraService.currentHeading,
                    isCapturing: isRecording,
                    capturedIndices: cameraService.capturedAngleIndices,
                    targetAngles: cameraService.targetAngles,
                    nearestUncapturedIndex: cameraService.nearestUncapturedIndex
                )

                Spacer()

                // 撮影コントロール
                controlsView
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            cameraService.setupCamera()
        }
        .onDisappear {
            cameraService.stopSession()
        }
        .onChange(of: cameraService.isCapturing) { _, newValue in
            // CameraServiceが自動停止した場合（全角度キャプチャ完了）
            if !newValue && isRecording {
                finishCapture()
            }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(item: $capturedSpace) { space in
            ProcessingView(space: space)
                .environmentObject(appState)
        }
    }

    // MARK: - ヘッダー

    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            // 撮影カウンター + 録画中インジケーター
            HStack(spacing: 6) {
                if isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                }
                Image(systemName: "camera.fill")
                    .font(.caption)
                Text("\(cameraService.photoCount) / \(cameraService.targetPhotoCount)")
                    .font(.headline.monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            Spacer()

            // プレースホルダー（レイアウト対称性のため）
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal)
    }

    // MARK: - コントロール

    private var controlsView: some View {
        VStack(spacing: 20) {
            // ガイドテキスト
            Text(guideText)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 50) {
                // 録画開始/停止ボタン
                Button {
                    toggleRecording()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? .red.opacity(0.3) : .clear)
                            .frame(width: 76, height: 76)

                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 76, height: 76)

                        if isRecording {
                            // 停止アイコン（四角）
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.red)
                                .frame(width: 28, height: 28)
                        } else {
                            // 録画開始アイコン（赤い丸）
                            Circle()
                                .fill(.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }

                // 完了ボタン
                Button {
                    finishCapture()
                } label: {
                    Text("完了")
                        .font(.headline)
                        .foregroundStyle(canFinish ? .cyan : .white.opacity(0.3))
                        .frame(width: 50, height: 50)
                }
                .disabled(!canFinish)
            }
        }
    }

    /// 撮影完了可能かどうか
    private var canFinish: Bool {
        cameraService.photoCount >= 8
    }

    /// ガイドテキスト
    private var guideText: String {
        if cameraService.photoCount == 0 && !isRecording {
            return "中央に立ち、ボタンを押して撮影を開始してください"
        } else if isRecording {
            return "ゆっくりと360度回転してください..."
        } else if canFinish {
            return "「完了」を押すか、再度録画して追加撮影できます"
        } else {
            return "あと\(8 - cameraService.photoCount)枚以上撮影してください"
        }
    }

    // MARK: - アクション

    /// 録画の開始/停止を切り替え
    private func toggleRecording() {
        if isRecording {
            isRecording = false
            cameraService.stopRecording()
        } else {
            isRecording = true
            cameraService.startRecording()
        }
    }

    /// 撮影を完了して処理画面へ
    private func finishCapture() {
        isRecording = false
        cameraService.stopRecording()

        var space = CapturedSpace(name: "空間 \(formattedNow)")
        let savedPaths = cameraService.savePhotos(for: space.id)
        space.capturedImagePaths = savedPaths
        space.status = .captured
        space.thumbnailPath = savedPaths.first

        appState.saveSpace(space)
        capturedSpace = space
    }

    /// 現在時刻のフォーマット
    private var formattedNow: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date())
    }
}

// MARK: - カメラプレビュービュー（UIViewRepresentable）

/// AVCaptureSessionのプレビューを表示するUIKit ビュー
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// カメラプレビュー用のUIViewサブクラス
final class CameraPreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            guard let session else { return }
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = bounds
            layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
        }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

#Preview {
    CaptureView()
        .environmentObject(AppState())
}
