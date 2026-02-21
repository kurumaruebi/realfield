// MotionService.swift
// RealField
//
// CoreMotionを使用したジャイロスコープ・加速度センサー制御
// Splatビューアでの視点移動に使用する

import Foundation
import CoreMotion
import simd

/// デバイスのモーションデータを提供するサービス
@MainActor
final class MotionService: ObservableObject {
    // MARK: - 公開プロパティ

    /// 現在の回転姿勢（オイラー角、ラジアン）
    @Published var attitude: simd_float3 = .zero
    /// 回転レート（ラジアン/秒）
    @Published var rotationRate: simd_float3 = .zero
    /// ユーザーの加速度（重力を除く）
    @Published var userAcceleration: simd_float3 = .zero
    /// ジャイロスコープが利用可能か
    @Published var isAvailable: Bool = false

    // MARK: - 内部プロパティ

    private let motionManager = CMMotionManager()
    /// 基準姿勢（キャリブレーション用）
    private var referenceAttitude: CMAttitude?
    /// 更新間隔（60Hz）
    private let updateInterval: TimeInterval = 1.0 / 60.0

    // MARK: - 初期化

    init() {
        isAvailable = motionManager.isDeviceMotionAvailable
    }

    // MARK: - モーション制御

    /// モーション更新を開始する
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            isAvailable = false
            return
        }

        motionManager.deviceMotionUpdateInterval = updateInterval

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let self, let motion else { return }

            // 基準姿勢が未設定なら現在の姿勢を基準にする
            if self.referenceAttitude == nil {
                self.referenceAttitude = motion.attitude.copy() as? CMAttitude
            }

            // 基準姿勢からの相対的な姿勢を計算
            if let ref = self.referenceAttitude {
                let relativeAttitude = motion.attitude.copy() as! CMAttitude
                relativeAttitude.multiply(byInverseOf: ref)

                self.attitude = simd_float3(
                    Float(relativeAttitude.pitch),
                    Float(relativeAttitude.yaw),
                    Float(relativeAttitude.roll)
                )
            }

            self.rotationRate = simd_float3(
                Float(motion.rotationRate.x),
                Float(motion.rotationRate.y),
                Float(motion.rotationRate.z)
            )

            self.userAcceleration = simd_float3(
                Float(motion.userAcceleration.x),
                Float(motion.userAcceleration.y),
                Float(motion.userAcceleration.z)
            )
        }

        isAvailable = true
    }

    /// モーション更新を停止する
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
        referenceAttitude = nil
    }

    /// 基準姿勢をリセットする（現在の向きを正面にする）
    func recalibrate() {
        referenceAttitude = nil
    }

    // MARK: - ビューア用のカメラ変換行列を計算

    /// 現在の姿勢からビュー回転行列を生成する
    var viewRotationMatrix: simd_float4x4 {
        let pitch = attitude.x
        let yaw = attitude.y
        let roll = attitude.z

        // X軸回転（ピッチ）
        let pitchMatrix = simd_float4x4(rows: [
            simd_float4(1, 0, 0, 0),
            simd_float4(0, cos(pitch), -sin(pitch), 0),
            simd_float4(0, sin(pitch), cos(pitch), 0),
            simd_float4(0, 0, 0, 1)
        ])

        // Y軸回転（ヨー）
        let yawMatrix = simd_float4x4(rows: [
            simd_float4(cos(yaw), 0, sin(yaw), 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(-sin(yaw), 0, cos(yaw), 0),
            simd_float4(0, 0, 0, 1)
        ])

        // Z軸回転（ロール）
        let rollMatrix = simd_float4x4(rows: [
            simd_float4(cos(roll), -sin(roll), 0, 0),
            simd_float4(sin(roll), cos(roll), 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        ])

        return yawMatrix * pitchMatrix * rollMatrix
    }
}
