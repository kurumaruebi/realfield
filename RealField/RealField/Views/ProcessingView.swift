// ProcessingView.swift
// RealField
//
// API処理の待機画面
// 撮影した画像をシーン生成APIに送信し、
// 3Dシーンの生成完了をポーリングで待つ

import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// 処理対象の空間データ
    let space: CapturedSpace

    @State private var progress: Double = 0
    @State private var statusText = "準備中..."
    @State private var isProcessing = false
    @State private var isCompleted = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showViewer = false
    @State private var splatFileURL: URL?

    /// ネットワーキングサービス
    private let networkingService = NetworkingService()

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(red: 0.07, green: 0.07, blue: 0.07)
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // 3Dアニメーションアイコン
                    processingAnimation
                        .frame(width: 160, height: 160)

                    // ステータステキスト
                    VStack(spacing: 8) {
                        Text(statusText)
                            .font(.title3.bold())
                            .foregroundStyle(.white)

                        Text("しばらくお待ちください（30秒〜5分）")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    // プログレスバー
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(CustomProgressStyle())
                            .frame(height: 8)
                            .padding(.horizontal, 40)

                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // 画像枚数の表示
                    HStack(spacing: 20) {
                        InfoBadge(
                            icon: "photo.stack",
                            value: "\(space.capturedImagePaths.count)",
                            label: "撮影枚数"
                        )
                        InfoBadge(
                            icon: "arrow.up.circle",
                            value: isProcessing ? "送信済" : "待機中",
                            label: "アップロード"
                        )
                    }

                    Spacer()

                    // 完了ボタン / キャンセルボタン
                    if isCompleted {
                        Button {
                            showViewer = true
                        } label: {
                            HStack {
                                Image(systemName: "cube.transparent.fill")
                                Text("3Dシーンを表示")
                            }
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Text("キャンセル")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .task {
                await startProcessing()
            }
            .alert("処理エラー", isPresented: $showError) {
                Button("再試行") {
                    Task { await startProcessing() }
                }
                Button("閉じる") { dismiss() }
            } message: {
                Text(errorMessage)
            }
            .fullScreenCover(isPresented: $showViewer) {
                if let url = splatFileURL {
                    SplatViewerView(space: space, fileURL: url)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 処理ロジック

    /// API処理を開始する
    private func startProcessing() async {
        guard !isProcessing else { return }
        isProcessing = true

        do {
            // APIキーを確認
            let apiKey = appState.apiKey
            guard !apiKey.isEmpty else {
                throw APIError.invalidAPIKey
            }

            statusText = "画像を準備中..."
            progress = 0.05

            // 画像パスを確認（メモリにはまだ読み込まない）
            let imagePaths = space.capturedImagePaths
            guard !imagePaths.isEmpty else {
                throw APIError.noData
            }

            statusText = "APIに送信中..."

            // API呼び出し（ファイルパスを渡して1枚ずつ処理）
            let fileURL = try await networkingService.generateSplat(
                from: imagePaths,
                apiKey: apiKey,
                progressHandler: { p in
                    Task { @MainActor in
                        progress = p
                        updateStatusText(progress: p)
                    }
                }
            )

            // 完了処理
            await MainActor.run {
                splatFileURL = fileURL
                progress = 1.0
                statusText = "生成完了!"
                isCompleted = true
                isProcessing = false

                // 空間データを更新
                updateSpaceStatus(fileURL: fileURL)
            }

        } catch {
            await MainActor.run {
                isProcessing = false
                errorMessage = error.localizedDescription
                showError = true
                statusText = "エラーが発生しました"
            }
        }
    }

    /// 進捗に応じたステータステキストを更新
    private func updateStatusText(progress: Double) {
        switch progress {
        case 0..<0.1: statusText = "画像を準備中..."
        case 0.1..<0.2: statusText = "APIに送信中..."
        case 0.2..<0.5: statusText = "3Dシーンを生成中..."
        case 0.5..<0.8: statusText = "3Dシーンを最適化中..."
        case 0.8..<0.95: statusText = "ファイルをダウンロード中..."
        case 0.95...: statusText = "完了処理中..."
        default: break
        }
    }

    /// 空間データのステータスを更新
    private func updateSpaceStatus(fileURL: URL) {
        if let index = appState.savedSpaces.firstIndex(where: { $0.id == space.id }) {
            let relativePath = fileURL.lastPathComponent
            appState.savedSpaces[index].splatFilePath = "splats/\(relativePath)"
            appState.savedSpaces[index].status = .completed
        }
    }

    // MARK: - アニメーション

    @State private var rotationAngle: Double = 0

    private var processingAnimation: some View {
        ZStack {
            // 外枠リング
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.white, .white.opacity(0.3), .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(rotationAngle))

            // 内部リング
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 2)
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-rotationAngle * 0.7))

            // 中心アイコン
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "cube.transparent")
                .font(.system(size: 40))
                .foregroundStyle(isCompleted ? .green : .white)
                .scaleEffect(isCompleted ? 1.2 : 1.0)
                .animation(.spring(response: 0.5), value: isCompleted)
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

// MARK: - カスタムプログレスバースタイル

struct CustomProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景トラック
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.1))
                    .frame(height: 8)

                // プログレスバー
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white)
                    .frame(
                        width: geometry.size.width * (configuration.fractionCompleted ?? 0),
                        height: 8
                    )
                    .animation(.easeInOut(duration: 0.3), value: configuration.fractionCompleted)
            }
        }
    }
}

// MARK: - 情報バッジ

struct InfoBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)

            Text(value)
                .font(.headline)
                .foregroundStyle(.white)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
