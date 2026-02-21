// NetworkingService.swift
// RealField
//
// シーン生成APIとの通信を担当するサービス
// フロー: メディアアップロード → シーン生成 → ポーリング → SPZダウンロード

import Foundation
import UIKit

/// API通信を担当するサービスクラス
actor NetworkingService {
    // MARK: - 設定

    /// APIのベースURL
    private let baseURL = "https://api.realfield.app/v1"
    /// URLSession
    private let urlSession: URLSession
    /// ポーリング間隔（秒）
    private let pollingInterval: TimeInterval = 5.0
    /// 最大待機時間（秒）
    private let maxWaitTime: TimeInterval = 600.0

    // MARK: - 初期化

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - パブリックAPI

    /// 画像ファイルパスからGaussian Splatを生成する（完全なフロー）
    func generateSplat(
        from imagePaths: [String],
        apiKey: String,
        prompt: String? = "realistic indoor scene captured from center",
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        guard !imagePaths.isEmpty else {
            throw APIError.noData
        }

        // 1. 画像を1枚ずつアップロードしてmedia_asset_idを取得
        progressHandler(0.02)
        let mediaAssetIds = try await uploadImages(
            imagePaths: imagePaths,
            apiKey: apiKey,
            progressHandler: progressHandler
        )

        // 2. ワールド生成タスクを作成
        progressHandler(0.15)
        let operationId = try await createGeneration(
            mediaAssetIds: mediaAssetIds,
            imageCount: imagePaths.count,
            apiKey: apiKey,
            prompt: prompt
        )

        // 3. オペレーション完了をポーリングで待機
        let sceneData = try await pollOperation(
            operationId: operationId,
            apiKey: apiKey,
            progressHandler: progressHandler
        )

        // 4. SPZファイルをダウンロード
        progressHandler(0.9)
        let localURL = try await downloadSplatFile(from: sceneData)

        progressHandler(1.0)
        return localURL
    }

    // MARK: - 画像アップロード

    /// 画像を1枚ずつアップロードしてmedia_asset_idの配列を返す
    private func uploadImages(
        imagePaths: [String],
        apiKey: String,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> [String] {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            throw APIError.noData
        }

        var mediaAssetIds: [String] = []
        mediaAssetIds.reserveCapacity(imagePaths.count)

        for (index, path) in imagePaths.enumerated() {
            // 画像を読み込み・リサイズ
            let fullURL = documentsURL.appendingPathComponent(path)
            guard let imageData = try? Data(contentsOf: fullURL),
                  let image = UIImage(data: imageData) else { continue }

            let resized = resizeImage(image, maxDimension: 1024)
            guard let jpegData = resized.jpegData(compressionQuality: 0.8) else { continue }

            let fileName = "capture_\(String(format: "%02d", index)).jpg"

            // Step 1: アップロードURLを取得
            let prepareResponse = try await prepareUpload(
                fileName: fileName,
                apiKey: apiKey
            )

            // Step 2: 署名付きURLにアップロード
            try await uploadToSignedURL(
                data: jpegData,
                uploadInfo: prepareResponse.uploadInfo
            )

            mediaAssetIds.append(prepareResponse.mediaAsset.id)

            // 進捗: 0.02〜0.15
            let uploadProgress = 0.02 + (Double(index + 1) / Double(imagePaths.count)) * 0.13
            progressHandler(uploadProgress)
        }

        guard !mediaAssetIds.isEmpty else {
            throw APIError.noData
        }

        return mediaAssetIds
    }

    /// メディアアセットのアップロードを準備する
    private func prepareUpload(fileName: String, apiKey: String) async throws -> MediaAssetPrepareResponse {
        let url = URL(string: "\(baseURL)/media-assets:prepare_upload")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        let body = MediaAssetPrepareRequest(
            fileName: fileName,
            kind: "image",
            fileExtension: "jpg"
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw parseAPIError(statusCode: httpResponse.statusCode, data: data)
        }

        return try decodeResponse(MediaAssetPrepareResponse.self, from: data, endpoint: "prepare_upload")
    }

    /// 署名付きURLにファイルをアップロードする
    private func uploadToSignedURL(data: Data, uploadInfo: UploadInfo) async throws {
        guard let url = URL(string: uploadInfo.uploadUrl) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = uploadInfo.uploadMethod
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        // APIが要求するヘッダーを設定
        for (key, value) in uploadInfo.requiredHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await urlSession.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: 0, message: "画像アップロードに失敗しました")
        }
    }

    // MARK: - シーン生成

    /// シーン生成タスクを作成する
    private func createGeneration(
        mediaAssetIds: [String],
        imageCount: Int,
        apiKey: String,
        prompt: String?
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/scenes:generate")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        // マルチイメージプロンプトを構築（均等角度配分）
        let angleStep = 360.0 / Double(imageCount)
        let multiImageEntries = mediaAssetIds.enumerated().map { index, assetId in
            MultiImageEntry(
                azimuth: Int(Double(index) * angleStep),
                content: ImageContent(
                    source: "media_asset",
                    mediaAssetId: assetId
                )
            )
        }

        let body = SceneGenerateRequest(
            displayName: "RealField Capture",
            scenePrompt: ScenePrompt(
                type: "multi-image",
                textPrompt: prompt,
                multiImagePrompt: multiImageEntries
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw parseAPIError(statusCode: httpResponse.statusCode, data: data)
        }

        let operation = try decodeResponse(OperationResponse.self, from: data, endpoint: "scenes:generate")
        return operation.operationId
    }

    // MARK: - ポーリング

    /// オペレーション完了をポーリングで待機する
    private func pollOperation(
        operationId: String,
        apiKey: String,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> SceneData {
        let startTime = Date()

        while true {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > maxWaitTime {
                throw APIError.timeout
            }

            let operation = try await fetchOperation(
                operationId: operationId,
                apiKey: apiKey
            )

            if operation.done {
                if let error = operation.error {
                    throw APIError.taskFailed(error.message ?? "不明なエラー")
                }

                guard let sceneData = operation.response?.scene else {
                    throw APIError.noData
                }

                return sceneData
            }

            // 進捗を更新（0.15〜0.9の範囲）
            let progress = min(elapsed / maxWaitTime, 0.8)
            let mappedProgress = 0.15 + progress * 0.75
            progressHandler(mappedProgress)

            try await Task.sleep(for: .seconds(pollingInterval))
        }
    }

    /// オペレーションステータスを1回取得する
    private func fetchOperation(
        operationId: String,
        apiKey: String
    ) async throws -> OperationResponse {
        let url = URL(string: "\(baseURL)/operations/\(operationId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw parseAPIError(statusCode: httpResponse.statusCode, data: data)
        }

        return try decodeResponse(OperationResponse.self, from: data, endpoint: "operations/\(operationId)")
    }

    // MARK: - ファイルダウンロード

    /// SPZファイルをダウンロードしてローカルに保存する
    private func downloadSplatFile(from sceneData: SceneData) async throws -> URL {
        // full_res → 500k → 100k の優先順でURLを取得
        guard let spzUrls = sceneData.assets?.splats?.spzUrls,
              let downloadURLString = spzUrls.fullRes ?? spzUrls.medium ?? spzUrls.small else {
            throw APIError.noData
        }

        guard let url = URL(string: downloadURLString) else {
            throw APIError.invalidURL
        }

        let (tempURL, response) = try await urlSession.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        // ローカルに保存
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            throw APIError.noData
        }

        let splatsDir = documentsURL.appendingPathComponent("splats", isDirectory: true)
        try? fileManager.createDirectory(at: splatsDir, withIntermediateDirectories: true)

        let fileName = "splat_\(UUID().uuidString).spz"
        let destinationURL = splatsDir.appendingPathComponent(fileName)

        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: tempURL, to: destinationURL)

        return destinationURL
    }

    // MARK: - ヘルパー

    /// JSONデコードを試み、失敗時にレスポンスをログ出力する
    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let rawJSON = String(data: data, encoding: .utf8) ?? "(デコード不可)"
            print("[\(endpoint)] デコードエラー: \(error)")
            print("[\(endpoint)] レスポンスJSON: \(rawJSON)")
            throw APIError.decodingError(error)
        }
    }

    /// APIエラーレスポンスを解析する
    private func parseAPIError(statusCode: Int, data: Data) -> APIError {
        if statusCode == 401 {
            return .invalidAPIKey
        }

        if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return .serverError(statusCode: statusCode, message: errorResponse.error.message)
        }

        // フォールバック: JSONの文字列フィールドからメッセージを探す
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String ?? json["error"] as? String {
            return .serverError(statusCode: statusCode, message: message)
        }

        return .serverError(statusCode: statusCode, message: "不明なエラー")
    }

    /// 画像を指定された最大寸法にリサイズする
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)

        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - デモ用モック

    /// APIを使わずにデモ用のダミー処理を実行する
    func generateSplatDemo(
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        for i in 0...10 {
            let progress = Double(i) / 10.0
            progressHandler(progress)
            try await Task.sleep(for: .seconds(0.5))
        }

        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            throw APIError.noData
        }

        let demoFile = documentsURL.appendingPathComponent("splats/demo.ply")

        if !fileManager.fileExists(atPath: demoFile.path) {
            let splatsDir = documentsURL.appendingPathComponent("splats", isDirectory: true)
            try? fileManager.createDirectory(at: splatsDir, withIntermediateDirectories: true)
            let header = """
            ply
            format binary_little_endian 1.0
            element vertex 0
            property float x
            property float y
            property float z
            end_header

            """
            try header.data(using: .utf8)?.write(to: demoFile)
        }

        return demoFile
    }
}
