#!/usr/bin/env swift
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let rawDir = repoRoot.appendingPathComponent("website/.screenshots-raw", isDirectory: true)
let publicDir = repoRoot.appendingPathComponent("website/public", isDirectory: true)

func loadBitmap(from path: String) -> NSBitmapImageRep? {
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        return nil
    }

    rep.size = NSSize(width: width, height: height)
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return rep
}

let rawFiles = (try? FileManager.default.contentsOfDirectory(atPath: rawDir.path)) ?? []
let workspaceFiles = rawFiles.filter { $0.hasPrefix("workspace-") && $0.hasSuffix(".png") }.sorted()

guard !workspaceFiles.isEmpty else {
    fputs("prepare-website-screenshots: no workspace-*.png files in \(rawDir.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: publicDir, withIntermediateDirectories: true)

for file in workspaceFiles {
    let source = rawDir.appendingPathComponent(file).path
    let destination = publicDir.appendingPathComponent(file).path

    guard let rep = loadBitmap(from: source),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("prepare-website-screenshots: failed to process \(source)\n", stderr)
        exit(1)
    }

    try png.write(to: URL(fileURLWithPath: destination))
    fputs(
        "prepare-website-screenshots: wrote \(destination) (\(rep.pixelsWide)x\(rep.pixelsHigh))\n",
        stderr
    )
}

// Keep legacy dashboard asset name in sync for any older references.
let dashboardSource = publicDir.appendingPathComponent("workspace-dashboard.png")
let dashboardLegacy = publicDir.appendingPathComponent("app-screenshot-dashboard.png")
if FileManager.default.fileExists(atPath: dashboardSource.path) {
    try FileManager.default.removeItem(at: dashboardLegacy)
    try FileManager.default.copyItem(at: dashboardSource, to: dashboardLegacy)
    fputs("prepare-website-screenshots: synced app-screenshot-dashboard.png\n", stderr)
}
