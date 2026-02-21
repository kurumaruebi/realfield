// APIModels.swift
// RealField
//
// シーン生成APIのリクエスト/レスポンスモデル定義

import Foundation

// MARK: - メディアアセットアップロード

/// メディアアセットアップロード準備リクエスト
struct MediaAssetPrepareRequest: Encodable {
    let fileName: String
    let kind: String
    let fileExtension: String

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case kind
        case fileExtension = "extension"
    }
}

/// メディアアセットアップロード準備レスポンス
struct MediaAssetPrepareResponse: Decodable {
    let mediaAsset: MediaAsset
    let uploadInfo: UploadInfo

    enum CodingKeys: String, CodingKey {
        case mediaAsset = "media_asset"
        case uploadInfo = "upload_info"
    }
}

struct MediaAsset: Decodable {
    let id: String
}

struct UploadInfo: Decodable {
    let uploadUrl: String
    let uploadMethod: String
    let requiredHeaders: [String: String]

    enum CodingKeys: String, CodingKey {
        case uploadUrl = "upload_url"
        case uploadMethod = "upload_method"
        case requiredHeaders = "required_headers"
    }
}

// MARK: - シーン生成

/// シーン生成リクエスト
struct SceneGenerateRequest: Encodable {
    let displayName: String?
    let scenePrompt: ScenePrompt

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case scenePrompt = "scene_prompt"
    }
}

struct ScenePrompt: Encodable {
    let type: String
    let textPrompt: String?
    let multiImagePrompt: [MultiImageEntry]?

    enum CodingKeys: String, CodingKey {
        case type
        case textPrompt = "text_prompt"
        case multiImagePrompt = "multi_image_prompt"
    }
}

struct MultiImageEntry: Encodable {
    let azimuth: Int
    let content: ImageContent
}

struct ImageContent: Encodable {
    let source: String
    let mediaAssetId: String

    enum CodingKeys: String, CodingKey {
        case source
        case mediaAssetId = "media_asset_id"
    }
}

// MARK: - オペレーション（ポーリング）

/// オペレーションレスポンス
struct OperationResponse: Decodable {
    let operationId: String
    let done: Bool
    let error: OperationError?
    let metadata: OperationMetadata?
    let response: SceneResponse?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case done
        case error
        case metadata
        case response
    }
}

struct OperationError: Decodable {
    let code: Int?
    let message: String?
}

struct OperationMetadata: Decodable {
    let progress: ProgressInfo?
    let sceneId: String?

    enum CodingKeys: String, CodingKey {
        case progress
        case sceneId = "scene_id"
    }
}

struct ProgressInfo: Decodable {
    let status: String?
    let description: String?
}

// MARK: - シーンデータ

struct SceneResponse: Decodable {
    let scene: SceneData?
}

struct SceneData: Decodable {
    let id: String
    let displayName: String?
    let assets: SceneAssets?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case assets
    }
}

struct SceneAssets: Decodable {
    let splats: SplatAssets?
}

struct SplatAssets: Decodable {
    let spzUrls: SpzUrls?

    enum CodingKeys: String, CodingKey {
        case spzUrls = "spz_urls"
    }
}

struct SpzUrls: Decodable {
    let fullRes: String?
    let medium: String?
    let small: String?

    enum CodingKeys: String, CodingKey {
        case fullRes = "full_res"
        case medium = "500k"
        case small = "100k"
    }
}

// MARK: - APIエラー

/// APIエラーレスポンス（汎用）
struct APIErrorResponse: Decodable {
    let error: APIErrorDetail
}

struct APIErrorDetail: Decodable {
    let code: String?
    let message: String
}

/// アプリケーションで使用するAPIエラー型
enum APIError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)
    case taskFailed(String)
    case timeout
    case noData
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "APIキーが無効です。設定画面で正しいAPIキーを入力してください。"
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "サーバーエラー (\(code)): \(message)"
        case .decodingError(let error):
            return "データ解析エラー: \(error.localizedDescription)"
        case .taskFailed(let message):
            return "生成に失敗しました: \(message)"
        case .timeout:
            return "リクエストがタイムアウトしました。再試行してください。"
        case .noData:
            return "サーバーからデータが返されませんでした。"
        case .invalidURL:
            return "無効なURLです。"
        }
    }
}
