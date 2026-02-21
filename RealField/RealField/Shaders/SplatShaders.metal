// SplatShaders.metal
// RealField
//
// カスタムMetalシェーダー（将来の拡張用）
// メインのGaussian SplatレンダリングはMetalSplatterライブラリが担当する
// このファイルには追加のポストプロセスエフェクトなどを実装可能

#include <metal_stdlib>
using namespace metal;

// 現在はMetalSplatterライブラリがレンダリングを担当するため、
// カスタムシェーダーは使用していません。
// 将来的にポストプロセスエフェクト（ブルーム、トーンマッピング等）を
// 追加する場合はこのファイルに実装してください。
