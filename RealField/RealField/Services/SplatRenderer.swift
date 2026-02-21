// SplatRenderer.swift
// RealField
//
// MetalSplatterライブラリのラッパー
// .ply / .splat / .spz ファイルの読み込みと
// リアルタイムGaussian Splatレンダリングを担当する

import Foundation
import Metal
import MetalKit
import simd
import MetalSplatter
import SplatIO

// MARK: - SplatRendererWrapper

/// MetalSplatterをラップしてSwiftUIから簡単に使えるようにするクラス
@MainActor
final class SplatRendererWrapper: NSObject, ObservableObject {
    // MARK: - 公開プロパティ

    /// ファイル読み込み完了フラグ
    @Published var isLoaded: Bool = false
    /// 読み込んだSplat数
    @Published var splatCount: Int = 0
    /// エラーメッセージ
    @Published var errorMessage: String?
    /// 読み込み進捗（0.0〜1.0）
    @Published var loadProgress: Double = 0

    // MARK: - Metal関連

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var renderer: SplatRenderer?
    private var chunkId: ChunkID?

    // カメラ状態
    private var cameraPosition = simd_float3(0, 1.0, 0)
    private var cameraRotation = matrix_identity_float4x4
    private var fieldOfView: Float = 60.0
    private var viewportSize: SIMD2<Int> = SIMD2(1, 1)

    // MTKView設定
    private let colorFormat: MTLPixelFormat = .bgra8Unorm
    private let depthFormat: MTLPixelFormat = .depth32Float

    // MARK: - 初期化

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metalの初期化に失敗しました。このデバイスはMetalに対応していません。")
        }
        self.device = device
        self.commandQueue = commandQueue
        super.init()
    }

    // MARK: - レンダラーのセットアップ

    /// MTKView用にレンダラーを構成する
    func configure(for view: MTKView) {
        view.device = device
        view.colorPixelFormat = colorFormat
        view.depthStencilPixelFormat = depthFormat
        view.clearColor = MTLClearColor(red: 0.03, green: 0.03, blue: 0.08, alpha: 1.0)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        do {
            renderer = try SplatRenderer(
                device: device,
                colorFormat: colorFormat,
                depthFormat: depthFormat,
                sampleCount: 1,
                maxViewCount: 1,        // モノスコピック（Vision Proなら2）
                maxSimultaneousRenders: 3
            )
        } catch {
            errorMessage = "レンダラーの初期化に失敗: \(error.localizedDescription)"
        }
    }

    // MARK: - ファイル読み込み

    /// Splatファイルを読み込む（.ply / .splat / .spz 対応）
    func loadFile(at url: URL) async {
        do {
            loadProgress = 0.1

            // AutodetectSceneReaderでファイル形式を自動判別
            let reader = try AutodetectSceneReader(url)
            let points = try await reader.readAll()

            loadProgress = 0.6

            guard !points.isEmpty else {
                errorMessage = "Splatデータが空です"
                return
            }

            // SplatChunkを作成してレンダラーに追加
            let chunk = try SplatChunk(device: device, from: points)

            loadProgress = 0.8

            if let renderer {
                // 既存のチャンクがあれば削除
                if let existingId = chunkId {
                    await renderer.removeChunk(existingId)
                }

                chunkId = await renderer.addChunk(
                    chunk,
                    sortByLocality: true,
                    enabled: true
                )
            }

            loadProgress = 1.0
            splatCount = points.count
            isLoaded = true

        } catch {
            errorMessage = "ファイル読み込みエラー: \(error.localizedDescription)"
        }
    }

    // MARK: - カメラ制御

    /// カメラの位置と回転を更新する
    func updateCamera(position: simd_float3, rotation: simd_float4x4) {
        cameraPosition = position
        cameraRotation = rotation
    }

    // MARK: - レンダリング

    /// 1フレームを描画する
    func performRender(in view: MTKView) {
        guard let renderer,
              isLoaded,
              renderer.isReadyToRender,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable else { return }

        let colorTexture = drawable.texture
        let width = Int(view.drawableSize.width)
        let height = Int(view.drawableSize.height)
        viewportSize = SIMD2(width, height)

        // 深度テクスチャを取得（MTKViewが管理）
        guard let depthTexture = view.depthStencilTexture else { return }

        // ビュー行列を構築（カメラの逆変換）
        let viewMatrix = cameraRotation.inverse * translationMatrix(-cameraPosition)

        // 射影行列を構築
        let aspectRatio = Float(width) / Float(height)
        let projectionMatrix = perspectiveMatrix(
            fovY: fieldOfView * .pi / 180.0,
            aspectRatio: aspectRatio,
            nearZ: 0.01,
            farZ: 100.0
        )

        // ビューポートを設定
        let viewport = SplatRenderer.ViewportDescriptor(
            viewport: MTLViewport(
                originX: 0, originY: 0,
                width: Double(width), height: Double(height),
                znear: 0.01, zfar: 100.0
            ),
            projectionMatrix: projectionMatrix,
            viewMatrix: viewMatrix,
            screenSize: viewportSize
        )

        // レンダリング実行
        do {
            let rendered = try renderer.render(
                viewports: [viewport],
                colorTexture: colorTexture,
                colorStoreAction: .store,
                depthTexture: depthTexture,
                rasterizationRateMap: nil,
                renderTargetArrayLength: 1,
                to: commandBuffer
            )

            if rendered {
                commandBuffer.present(drawable)
            }
            commandBuffer.commit()
        } catch {
            print("レンダリングエラー: \(error)")
        }
    }

    // MARK: - 行列ヘルパー

    private func translationMatrix(_ t: simd_float3) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = simd_float4(t.x, t.y, t.z, 1)
        return m
    }

    private func perspectiveMatrix(fovY: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let y = 1.0 / tan(fovY * 0.5)
        let x = y / aspectRatio
        let z = farZ / (nearZ - farZ)
        return simd_float4x4(columns: (
            simd_float4(x, 0, 0, 0),
            simd_float4(0, y, 0, 0),
            simd_float4(0, 0, z, -1),
            simd_float4(0, 0, z * nearZ, 0)
        ))
    }
}

// MARK: - MTKViewDelegate

extension SplatRendererWrapper: MTKViewDelegate {
    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // サイズ変更時の処理（必要に応じて追加）
    }

    nonisolated func draw(in view: MTKView) {
        Task { @MainActor in
            self.performRender(in: view)
        }
    }
}
