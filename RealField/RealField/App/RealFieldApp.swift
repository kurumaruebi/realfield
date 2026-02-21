// RealFieldApp.swift
// RealField - 空間キャプチャ＆3Dシーンビューアアプリ
//
// アプリのエントリポイント。NavigationStackベースのルーティングを管理する。

import SwiftUI

@main
struct RealFieldApp: App {
    // MARK: - 状態管理
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - アプリ全体の状態管理
/// アプリ全体で共有する状態を管理するObservableObject
@MainActor
final class AppState: ObservableObject {
    /// 保存済みの空間データ一覧
    @Published var savedSpaces: [CapturedSpace] = []
    /// APIキー（UserDefaultsから復元）
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "realfield_api_key")
        }
    }

    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "realfield_api_key") ?? ""
        loadSavedSpaces()
    }

    /// 保存済みの空間データを読み込む
    func loadSavedSpaces() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let spacesDir = documentsURL.appendingPathComponent("spaces", isDirectory: true)

        guard fileManager.fileExists(atPath: spacesDir.path) else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(at: spacesDir, includingPropertiesForKeys: [.creationDateKey])
            savedSpaces = contents.compactMap { url -> CapturedSpace? in
                guard url.pathExtension == "json" else { return nil }
                guard let data = try? Data(contentsOf: url),
                      let space = try? JSONDecoder().decode(CapturedSpace.self, from: data) else { return nil }
                return space
            }.sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("空間データの読み込みエラー: \(error)")
        }
    }

    /// 新しい空間データを保存する
    func saveSpace(_ space: CapturedSpace) {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let spacesDir = documentsURL.appendingPathComponent("spaces", isDirectory: true)

        // ディレクトリが存在しなければ作成
        if !fileManager.fileExists(atPath: spacesDir.path) {
            try? fileManager.createDirectory(at: spacesDir, withIntermediateDirectories: true)
        }

        let fileURL = spacesDir.appendingPathComponent("\(space.id.uuidString).json")
        if let data = try? JSONEncoder().encode(space) {
            try? data.write(to: fileURL)
        }

        savedSpaces.insert(space, at: 0)
    }

    /// 空間データを削除する
    func deleteSpace(_ space: CapturedSpace) {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        // JSONメタデータを削除
        let jsonURL = documentsURL.appendingPathComponent("spaces/\(space.id.uuidString).json")
        try? fileManager.removeItem(at: jsonURL)

        // Splatファイルを削除
        if let splatPath = space.splatFilePath {
            let splatURL = documentsURL.appendingPathComponent(splatPath)
            try? fileManager.removeItem(at: splatURL)
        }

        savedSpaces.removeAll { $0.id == space.id }
    }
}
