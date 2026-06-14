#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

let sourcePath = CommandLine.arguments.dropFirst().first
    ?? repoRoot.appendingPathComponent("app/Nucleus/Assets/AppIconSource.raw.png").path
let outputPath = CommandLine.arguments.dropFirst().dropFirst().first
    ?? repoRoot.appendingPathComponent("website/public/app-icon.png").path
let heroOutputPath = repoRoot.appendingPathComponent("website/public/hero.png").path

// Strip the outer matte and dark bezel so the website icon reads lighter on the page.
let blackThreshold = 58
let feather = 28
let innerTrim = 10

func makeTransparentBitmap(from path: String) -> (rep: NSBitmapImageRep, width: Int, height: Int)? {
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

    guard let data = rep.bitmapData else { return nil }
    let bytesPerRow = rep.bytesPerRow

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            let red = Int(data[offset])
            let green = Int(data[offset + 1])
            let blue = Int(data[offset + 2])
            let luminance = (red * 299 + green * 587 + blue * 114) / 1000

            if luminance <= blackThreshold {
                data[offset] = 0
                data[offset + 1] = 0
                data[offset + 2] = 0
                data[offset + 3] = 0
            } else if luminance < blackThreshold + feather {
                let alpha = (luminance - blackThreshold) * 255 / feather
                data[offset + 3] = UInt8(min(255, max(0, alpha)))
            } else {
                data[offset + 3] = 255
            }
        }
    }

    return (rep, width, height)
}

func cropToOpaqueBounds(
    _ rep: NSBitmapImageRep,
    width: Int,
    height: Int,
    padding: Int = 0,
    trim: Int = 0
) -> NSBitmapImageRep {
    guard let data = rep.bitmapData else { return rep }
    let bytesPerRow = rep.bytesPerRow

    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0

    for y in 0..<height {
        for x in 0..<width {
            let alpha = data[y * bytesPerRow + x * 4 + 3]
            if alpha > 12 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    if maxX <= minX || maxY <= minY {
        return rep
    }

    minX = max(0, minX - padding + trim)
    minY = max(0, minY - padding + trim)
    maxX = min(width - 1, maxX + padding - trim)
    maxY = min(height - 1, maxY + padding - trim)

    let cropWidth = maxX - minX + 1
    let cropHeight = maxY - minY + 1

    guard let cropped = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: cropWidth,
        pixelsHigh: cropHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let cropData = cropped.bitmapData else {
        return rep
    }

    cropped.size = NSSize(
        width: rep.size.width * CGFloat(cropWidth) / CGFloat(width),
        height: rep.size.height * CGFloat(cropHeight) / CGFloat(height)
    )

    let cropBytesPerRow = cropped.bytesPerRow
    for y in 0..<cropHeight {
        for x in 0..<cropWidth {
            let src = (minY + y) * bytesPerRow + (minX + x) * 4
            let dst = y * cropBytesPerRow + x * 4
            cropData[dst] = data[src]
            cropData[dst + 1] = data[src + 1]
            cropData[dst + 2] = data[src + 2]
            cropData[dst + 3] = data[src + 3]
        }
    }

    return cropped
}

func padToSquare(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
    let width = rep.pixelsWide
    let height = rep.pixelsHigh
    let side = max(width, height)

    guard let square = NSBitmapImageRep(
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
    ), let squareData = square.bitmapData else {
        return rep
    }

    square.size = NSSize(
        width: rep.size.width * CGFloat(side) / CGFloat(max(width, 1)),
        height: rep.size.height * CGFloat(side) / CGFloat(max(height, 1))
    )

    let squareBytesPerRow = square.bytesPerRow
    for y in 0..<side {
        for x in 0..<side {
            let offset = y * squareBytesPerRow + x * 4
            squareData[offset] = 0
            squareData[offset + 1] = 0
            squareData[offset + 2] = 0
            squareData[offset + 3] = 0
        }
    }

    guard let sourceData = rep.bitmapData else { return rep }
    let sourceBytesPerRow = rep.bytesPerRow
    let offsetX = (side - width) / 2
    let offsetY = (side - height) / 2

    for y in 0..<height {
        for x in 0..<width {
            let src = y * sourceBytesPerRow + x * 4
            let dst = (offsetY + y) * squareBytesPerRow + (offsetX + x) * 4
            squareData[dst] = sourceData[src]
            squareData[dst + 1] = sourceData[src + 1]
            squareData[dst + 2] = sourceData[src + 2]
            squareData[dst + 3] = sourceData[src + 3]
        }
    }

    return square
}

guard let initial = makeTransparentBitmap(from: sourcePath) else {
    fputs("prepare-website-assets: failed to load \(sourcePath)\n", stderr)
    exit(1)
}

let cropped = padToSquare(
    cropToOpaqueBounds(
        initial.rep,
        width: initial.width,
        height: initial.height,
        trim: innerTrim
    )
)

guard let png = cropped.representation(using: .png, properties: [:]) else {
    fputs("prepare-website-assets: failed to encode PNG\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)

fputs("prepare-website-assets: wrote \(outputPath)\n", stderr)

let heroCropped = padToSquare(
    cropToOpaqueBounds(
        initial.rep,
        width: initial.width,
        height: initial.height,
        trim: innerTrim + 4
    )
)

guard let heroPNG = heroCropped.representation(using: .png, properties: [:]) else {
    fputs("prepare-website-assets: failed to encode hero PNG\n", stderr)
    exit(1)
}

let heroOutputURL = URL(fileURLWithPath: heroOutputPath)
try heroPNG.write(to: heroOutputURL)
fputs("prepare-website-assets: wrote \(heroOutputPath)\n", stderr)
