// ContentView.swift
// RealField
//
// ホーム画面：空間キャプチャの開始、保存済み空間一覧、設定画面へのナビゲーション

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showCapture = false
    @State private var showSettings = false
    @State private var selectedSpace: CapturedSpace?

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(red: 0.07, green: 0.07, blue: 0.07)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // メインコンテンツ
                    if appState.savedSpaces.isEmpty {
                        emptyStateView
                    } else {
                        savedSpacesListView
                    }

                    // キャプチャボタン（下部固定）
                    captureButton
                        .padding(.bottom, 30)
                }
            }
            .navigationTitle("RealField")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .fullScreenCover(isPresented: $showCapture) {
                CaptureView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(appState)
            }
            .sheet(item: $selectedSpace) { space in
                if space.status == .completed, space.splatFilePath != nil {
                    SplatViewerView(space: space)
                } else if space.status == .captured || space.status == .failed {
                    ProcessingView(space: space)
                        .environmentObject(appState)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - サブビュー

    /// 空の状態表示
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cube.transparent")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.6))

            Text("空間をキャプチャして\n3Dシーンを作成しましょう")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    /// 保存済み空間のリスト
    private var savedSpacesListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(appState.savedSpaces) { space in
                    SpaceCardView(space: space)
                        .onTapGesture {
                            selectedSpace = space
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                appState.deleteSpace(space)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    /// 大きなキャプチャボタン
    private var captureButton: some View {
        Button {
            // APIキーの確認
            if appState.apiKey.isEmpty {
                showSettings = true
            } else {
                showCapture = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                Text("空間をキャプチャ")
                    .font(.title3.bold())
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .white.opacity(0.1), radius: 15, y: 5)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - 空間カードビュー

/// 保存済み空間を表示するカード
struct SpaceCardView: View {
    let space: CapturedSpace

    var body: some View {
        HStack(spacing: 16) {
            // サムネイル / プレースホルダー
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.08))
                .frame(width: 70, height: 70)
                .overlay {
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(space.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(space.statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer()

            if space.status == .completed {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(16)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statusIcon: String {
        switch space.status {
        case .captured: return "photo.on.rectangle"
        case .uploading: return "arrow.up.circle"
        case .processing: return "gearshape.2"
        case .completed: return "cube.transparent.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch space.status {
        case .captured: return .orange
        case .uploading, .processing: return .white
        case .completed: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
