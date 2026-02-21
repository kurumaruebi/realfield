// SettingsView.swift
// RealField
//
// 設定画面：APIキーの入力・管理と各種設定

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var showAPIKey = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - APIキー設定
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("RealField API キー", systemImage: "key.fill")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        // APIキー入力フィールド
                        HStack {
                            Group {
                                if showAPIKey {
                                    TextField("sk-...", text: $apiKeyInput)
                                } else {
                                    SecureField("sk-...", text: $apiKeyInput)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // 保存ボタン
                        Button {
                            appState.apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("APIキーを保存")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        // ステータス表示
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.apiKey.isEmpty ? .red : .green)
                                .frame(width: 8, height: 8)
                            Text(appState.apiKey.isEmpty ? "未設定" : "設定済み")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("API設定")
                } footer: {
                    Text("APIキーを入力してください。キーはデバイスに安全に保存されます。")
                }

                // MARK: - カメラ設定
                Section("カメラ設定") {
                    HStack {
                        Label("撮影枚数", systemImage: "photo.on.rectangle")
                        Spacer()
                        Text("18枚")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("カメラ", systemImage: "camera")
                        Spacer()
                        Text("超広角優先")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("画質", systemImage: "sparkles")
                        Spacer()
                        Text("最高品質")
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - ビューア設定
                Section("ビューア設定") {
                    HStack {
                        Label("ジャイロスコープ", systemImage: "gyroscope")
                        Spacer()
                        Text("有効")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("レンダリング", systemImage: "cpu")
                        Spacer()
                        Text("Metal GPU")
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - データ管理
                Section("データ管理") {
                    HStack {
                        Label("保存済み空間", systemImage: "folder")
                        Spacer()
                        Text("\(appState.savedSpaces.count) 件")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("ストレージ使用量", systemImage: "internaldrive")
                        Spacer()
                        Text(storageUsageText)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("すべてのデータを削除", systemImage: "trash")
                    }
                }

                // MARK: - アプリ情報
                Section("アプリ情報") {
                    HStack {
                        Label("バージョン", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("ビルド", systemImage: "hammer")
                        Spacer()
                        Text("1")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("対応OS", systemImage: "iphone")
                        Spacer()
                        Text("iOS 17+")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiKeyInput = appState.apiKey
            }
            .alert("データ削除", isPresented: $showClearConfirm) {
                Button("削除", role: .destructive) {
                    clearAllData()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("保存済みのすべての空間データとSplatファイルが削除されます。この操作は取り消せません。")
            }
        }
    }

    // MARK: - ヘルパー

    /// ストレージ使用量を計算して表示する
    private var storageUsageText: String {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "不明"
        }

        let spacesDir = documentsURL.appendingPathComponent("spaces")
        let splatsDir = documentsURL.appendingPathComponent("splats")
        var totalSize: Int64 = 0

        for dir in [spacesDir, splatsDir] {
            if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    /// すべてのデータを削除する
    private func clearAllData() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let spacesDir = documentsURL.appendingPathComponent("spaces")
        let splatsDir = documentsURL.appendingPathComponent("splats")

        try? FileManager.default.removeItem(at: spacesDir)
        try? FileManager.default.removeItem(at: splatsDir)

        appState.savedSpaces.removeAll()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
