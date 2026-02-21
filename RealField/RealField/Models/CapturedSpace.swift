// CapturedSpace.swift
// RealField
//
// キャプチャされた空間のデータモデル

import Foundation

/// キャプチャされた空間を表すデータモデル
struct CapturedSpace: Identifiable, Codable {
    /// 一意な識別子
    let id: UUID
    /// 空間の名前（ユーザーが設定可能）
    var name: String
    /// 作成日時
    let createdAt: Date
    /// キャプチャした画像のファイルパス一覧（Documentsからの相対パス）
    var capturedImagePaths: [String]
    /// 生成されたSplatファイルのパス（Documentsからの相対パス）
    var splatFilePath: String?
    /// サムネイル画像のパス
    var thumbnailPath: String?
    /// 処理状態
    var status: ProcessingStatus

    /// 処理状態を表す列挙型
    enum ProcessingStatus: String, Codable {
        case captured       // 撮影完了、未処理
        case uploading      // API送信中
        case processing     // API処理中
        case completed      // Splat生成完了
        case failed         // 処理失敗
    }

    init(name: String = "新しい空間") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.capturedImagePaths = []
        self.splatFilePath = nil
        self.thumbnailPath = nil
        self.status = .captured
    }
}

// MARK: - ヘルパー
extension CapturedSpace {
    /// Documents ディレクトリ内の画像保存用フォルダURL
    var imageDirectoryURL: URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsURL.appendingPathComponent("spaces/\(id.uuidString)/images", isDirectory: true)
    }

    /// Splatファイルの完全なURL
    var splatFileURL: URL? {
        guard let splatPath = splatFilePath,
              let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsURL.appendingPathComponent(splatPath)
    }

    /// 日時のフォーマット済み文字列
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// ステータスの日本語表示
    var statusText: String {
        switch status {
        case .captured: return "未処理"
        case .uploading: return "アップロード中"
        case .processing: return "生成中"
        case .completed: return "完了"
        case .failed: return "失敗"
        }
    }
}
