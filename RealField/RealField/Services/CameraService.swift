// CameraService.swift
// RealField
//
// AVFoundationを使用したカメラ制御サービス
// ビデオフレームから角度ベースで自動キャプチャする

import AVFoundation
import UIKit
import CoreMotion
import Combine
import CoreImage

/// カメラ制御を担当するサービスクラス
@MainActor
final class CameraService: NSObject, ObservableObject {
    // MARK: - 公開プロパティ

    /// カメラプレビュー用のセッション
    @Published var session = AVCaptureSession()
    /// 撮影した写真の配列
    @Published var capturedPhotos: [CapturedPhoto] = []
    /// 現在の撮影枚数
    @Published var photoCount: Int = 0
    /// 目標撮影枚数
    let targetPhotoCount: Int = 18
    /// カメラの準備完了状態
    @Published var isReady: Bool = false
    /// エラーメッセージ
    @Published var errorMessage: String?
    /// 現在のデバイスの向き（度数、0〜360）
    @Published var currentHeading: Double = 0
    /// 撮影中（録画中）かどうか
    @Published var isCapturing: Bool = false
    /// キャプチャ済み角度のインデックスセット
    @Published var capturedAngleIndices: Set<Int> = []
    /// 最も近い未キャプチャ角度のインデックス
    @Published var nearestUncapturedIndex: Int? = nil
    /// ターゲット角度の配列
    @Published var targetAngles: [Double] = []

    // MARK: - 内部プロパティ

    private let videoOutput = AVCaptureVideoDataOutput()
    private let motionManager = CMMotionManager()
    private let sessionQueue = DispatchQueue(label: "com.realfield.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.realfield.camera.videooutput")
    private let ciContext = CIContext()
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    /// 撮影した写真のデータ
    struct CapturedPhoto {
        let image: UIImage
        let heading: Double
        let pitch: Double
        let index: Int
    }

    // MARK: - 初期化

    override init() {
        super.init()
        hapticFeedback.prepare()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - カメラセットアップ

    /// カメラセッションを構成して開始する
    func setupCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.errorMessage = "カメラへのアクセスが拒否されました。設定アプリから許可してください。"
                    }
                }
            }
        default:
            errorMessage = "カメラへのアクセスが拒否されました。設定アプリから許可してください。"
        }
    }

    /// AVCaptureSessionを構成する
    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // 超広角カメラを優先的に探す
            let camera = self.findBestCamera()
            guard let camera else {
                Task { @MainActor in
                    self.errorMessage = "利用可能なカメラが見つかりません。"
                }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)

                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }

                // ビデオ出力を設定
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]

                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }

                // フレームレートを10fpsに制限
                try camera.lockForConfiguration()
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 10)
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 10)
                camera.unlockForConfiguration()

                self.session.commitConfiguration()
                self.session.startRunning()

                Task { @MainActor in
                    self.isReady = true
                    self.startMotionUpdates()
                }
            } catch {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.errorMessage = "カメラの初期化に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    /// 超広角カメラを優先してデバイスを検索する
    private func findBestCamera() -> AVCaptureDevice? {
        if let ultraWide = AVCaptureDevice.default(
            .builtInUltraWideCamera,
            for: .video,
            position: .back
        ) {
            print("超広角カメラを使用します")
            return ultraWide
        }

        if let wide = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) {
            print("広角カメラを使用します")
            return wide
        }

        return AVCaptureDevice.default(for: .video)
    }

    // MARK: - モーション追跡

    /// デバイスのモーション（ジャイロ）更新を開始する
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: .main
        ) { [weak self] motion, _ in
            guard let motion else { return }
            let yaw = motion.attitude.yaw
            let heading = (yaw * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
            self?.currentHeading = heading
        }
    }

    /// モーション更新を停止する
    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - 録画（角度ベースキャプチャ）

    /// 録画を開始し、ターゲット角度を生成する
    func startRecording() {
        guard isReady else { return }

        // 現在の向きを基準に20°間隔で18個のターゲット角度を生成
        let startAngle = currentHeading
        targetAngles = (0..<targetPhotoCount).map { i in
            (startAngle + Double(i) * 20.0).truncatingRemainder(dividingBy: 360.0)
        }

        capturedPhotos = []
        capturedAngleIndices = []
        nearestUncapturedIndex = 0
        photoCount = 0
        isCapturing = true
    }

    /// 録画を停止する
    func stopRecording() {
        isCapturing = false
    }

    /// 現在のヘディングに最も近い未キャプチャ角度のインデックスを更新する
    private func updateNearestUncaptured() {
        guard !targetAngles.isEmpty else { return }

        var nearest: Int? = nil
        var minDiff = Double.infinity

        for i in 0..<targetAngles.count {
            guard !capturedAngleIndices.contains(i) else { continue }
            let diff = angleDifference(currentHeading, targetAngles[i])
            if diff < minDiff {
                minDiff = diff
                nearest = i
            }
        }

        nearestUncapturedIndex = nearest
    }

    /// 2つの角度間の最小差分（0〜180）を計算する
    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360.0)
        return min(diff, 360.0 - diff)
    }

    /// CMSampleBufferからUIImageを生成する
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - 保存

    /// 撮影した画像をファイルに保存する（角度順にソート）
    func savePhotos(for spaceId: UUID) -> [String] {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }

        let imageDir = documentsURL.appendingPathComponent("spaces/\(spaceId.uuidString)/images", isDirectory: true)

        try? fileManager.createDirectory(at: imageDir, withIntermediateDirectories: true)

        // 角度インデックス順にソート（APIに正しいazimuth順で渡すため）
        let sortedPhotos = capturedPhotos.sorted { $0.index < $1.index }

        var savedPaths: [String] = []

        for (index, photo) in sortedPhotos.enumerated() {
            if let jpegData = photo.image.jpegData(compressionQuality: 0.9) {
                let fileName = String(format: "capture_%02d.jpg", index)
                let filePath = imageDir.appendingPathComponent(fileName)

                do {
                    try jpegData.write(to: filePath)
                    savedPaths.append("spaces/\(spaceId.uuidString)/images/\(fileName)")
                } catch {
                    print("画像保存エラー: \(error)")
                }
            }
        }

        return savedPaths
    }

    /// セッションを停止する
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
        stopMotionUpdates()
    }

    // MARK: - エラー型

    enum CameraError: LocalizedError {
        case notReady
        case captureFailure(String)

        var errorDescription: String? {
            switch self {
            case .notReady:
                return "カメラの準備ができていません。"
            case .captureFailure(let reason):
                return "写真の撮影に失敗しました: \(reason)"
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Task { @MainActor in
            guard isCapturing else { return }

            // 最も近い未キャプチャ角度を更新
            updateNearestUncaptured()

            // 全角度キャプチャ済みなら停止
            guard capturedAngleIndices.count < targetPhotoCount else {
                stopRecording()
                return
            }

            // ターゲット角度との一致をチェック（±8°以内）
            for i in 0..<targetAngles.count {
                guard !capturedAngleIndices.contains(i) else { continue }

                let diff = angleDifference(currentHeading, targetAngles[i])
                if diff <= 8.0 {
                    // フレームからUIImageを生成
                    guard let image = imageFromSampleBuffer(sampleBuffer) else { return }

                    let photo = CapturedPhoto(
                        image: image,
                        heading: currentHeading,
                        pitch: 0,
                        index: i
                    )

                    capturedPhotos.append(photo)
                    capturedAngleIndices.insert(i)
                    photoCount = capturedAngleIndices.count

                    // ハプティックフィードバック
                    hapticFeedback.impactOccurred()
                    hapticFeedback.prepare()

                    break // 1フレームにつき1角度のみキャプチャ
                }
            }
        }
    }
}
