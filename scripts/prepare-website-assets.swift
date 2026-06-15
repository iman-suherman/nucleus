#!/usr/bin/env swift
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

let sourcePath = CommandLine.arguments.dropFirst().first
    ?? repoRoot.appendingPathComponent("app/Nucleus/Assets/AppIconSource.png").path
let outputPath = CommandLine.arguments.dropFirst().dropFirst().first
    ?? repoRoot.appendingPathComponent("website/public/app-icon.png").path
let heroOutputPath = repoRoot.appendingPathComponent("website/public/hero.png").path

func resizedPNG(from path: String, side: Int) -> Data? {
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let sourceSize = NSSize(width: cgImage.width, height: cgImage.height)
    let scale = min(CGFloat(side) / sourceSize.width, CGFloat(side) / sourceSize.height)
    let drawnSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let origin = NSPoint(
        x: (CGFloat(side) - drawnSize.width) / 2,
        y: (CGFloat(side) - drawnSize.height) / 2
    )

    NSGraphicsContext.current?.cgContext.draw(
        cgImage,
        in: NSRect(origin: origin, size: drawnSize)
    )

    return rep.representation(using: .png, properties: [:])
}

guard let iconPNG = resizedPNG(from: sourcePath, side: 512) else {
    fputs("prepare-website-assets: failed to load \(sourcePath)\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try iconPNG.write(to: outputURL)
fputs("prepare-website-assets: wrote \(outputPath)\n", stderr)

guard let heroPNG = resizedPNG(from: sourcePath, side: 768) else {
    fputs("prepare-website-assets: failed to encode hero PNG\n", stderr)
    exit(1)
}

let heroOutputURL = URL(fileURLWithPath: heroOutputPath)
try heroPNG.write(to: heroOutputURL)
fputs("prepare-website-assets: wrote \(heroOutputPath)\n", stderr)
