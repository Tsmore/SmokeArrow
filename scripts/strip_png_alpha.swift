#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct CLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func hex(_ value: UInt32) -> String {
    String(format: "%06X", value & 0x00FF_FFFF)
}

func loadCGImage(from url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw CLIError(message: "画像を読み込めませんでした: \(url.path)")
    }
    guard let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw CLIError(message: "CGImageを生成できませんでした: \(url.path)")
    }
    return cgImage
}

func dominantOpaqueRGB(from cgImage: CGImage, sampleStride: Int = 6) -> UInt32 {
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return 0xFFFFFF }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let bitsPerComponent = 8

    var data = [UInt8](repeating: 0, count: bytesPerRow * height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    data.withUnsafeMutableBytes { rawBuf in
        guard let ctx = CGContext(
            data: rawBuf.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    var counts: [UInt32: Int] = [:]
    counts.reserveCapacity(2048)

    for y in stride(from: 0, to: height, by: sampleStride) {
        let rowBase = y * bytesPerRow
        for x in stride(from: 0, to: width, by: sampleStride) {
            let i = rowBase + x * bytesPerPixel
            let r = UInt32(data[i + 0])
            let g = UInt32(data[i + 1])
            let b = UInt32(data[i + 2])
            let a = UInt32(data[i + 3])
            if a >= 250 {
                let rgb = (r << 16) | (g << 8) | b
                counts[rgb, default: 0] += 1
            }
        }
    }

    if let (rgb, _) = counts.max(by: { $0.value < $1.value }) {
        return rgb
    }
    return 0xFFFFFF
}

func stripAlpha(in inputURL: URL, outputURL: URL) throws -> (backgroundRGB: UInt32) {
    let sourceImage = try loadCGImage(from: inputURL)
    let width = sourceImage.width
    let height = sourceImage.height

    let bgRGB = dominantOpaqueRGB(from: sourceImage)
    let r = CGFloat((bgRGB >> 16) & 0xFF) / 255.0
    let g = CGFloat((bgRGB >> 8) & 0xFF) / 255.0
    let b = CGFloat(bgRGB & 0xFF) / 255.0

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let bitsPerComponent = 8
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw CLIError(message: "描画コンテキストを作成できませんでした")
    }

    ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let outImage = ctx.makeImage() else {
        throw CLIError(message: "出力CGImageを生成できませんでした")
    }

    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw CLIError(message: "出力先を作成できませんでした: \(outputURL.path)")
    }

    CGImageDestinationAddImage(destination, outImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CLIError(message: "PNGの書き出しに失敗しました: \(outputURL.path)")
    }

    return (backgroundRGB: bgRGB)
}

let args = CommandLine.arguments.dropFirst()
guard let inputPath = args.first else {
    fputs("Usage: strip_png_alpha.swift <input.png> [output.png]\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: inputPath)
let outputURL: URL
if args.count >= 2, let out = args.dropFirst().first {
    outputURL = URL(fileURLWithPath: out)
} else {
    outputURL = inputURL
}

let tmpURL = outputURL.deletingLastPathComponent().appendingPathComponent(".\(outputURL.lastPathComponent).tmp")

do {
    let result = try stripAlpha(in: inputURL, outputURL: tmpURL)
    try FileManager.default.removeItem(at: outputURL)
    try FileManager.default.moveItem(at: tmpURL, to: outputURL)
    print("OK: alpha除去 -> \(outputURL.path) (bg=#\(hex(result.backgroundRGB)))")
} catch {
    _ = try? FileManager.default.removeItem(at: tmpURL)
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

