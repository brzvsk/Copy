#!/usr/bin/env swift
//
// make-icon.swift
//
// Deterministically renders the Copy app icon: a rounded-rect app tile in a
// restrained graphite gradient, holding a clipboard glyph with a single card
// lifting off it (echoing the shelf). Pure Core Graphics + AppKit's PNG
// encoder, no external assets, no randomness.
//
// Run with: swift Scripts/make-icon.swift
// Writes all 10 required PNGs into Copy/Assets.xcassets/AppIcon.appiconset/.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Palette (restrained graphite/neutral -- no colored stripe, no accent slab)

enum Palette {
    static let tileTop = CGColor(red: 0.482, green: 0.494, blue: 0.529, alpha: 1)      // #7B7E87
    static let tileBottom = CGColor(red: 0.184, green: 0.192, blue: 0.216, alpha: 1)   // #2F3137
    static let tileHighlight = CGColor(red: 1, green: 1, blue: 1, alpha: 0.14)
    static let clear = CGColor(red: 1, green: 1, blue: 1, alpha: 0)
    static let tileVignette = CGColor(red: 0, green: 0, blue: 0, alpha: 0.16)
    static let vignetteClear = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

    static let boardFill = CGColor(red: 0.933, green: 0.937, blue: 0.945, alpha: 1)    // #EEEFF1
    static let boardStroke = CGColor(red: 0.667, green: 0.678, blue: 0.702, alpha: 0.9)
    static let boardShadow = CGColor(red: 0, green: 0, blue: 0, alpha: 0.32)

    static let clipFill = CGColor(red: 0.694, green: 0.706, blue: 0.733, alpha: 1)     // #B1B4BB
    static let clipStroke = CGColor(red: 0.510, green: 0.522, blue: 0.549, alpha: 1)

    static let cardFill = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let cardStroke = CGColor(red: 0.804, green: 0.812, blue: 0.827, alpha: 1)
    static let cardShadow = CGColor(red: 0, green: 0, blue: 0, alpha: 0.34)

    static let lineColor = CGColor(red: 0.729, green: 0.737, blue: 0.757, alpha: 1)
}

// MARK: - Geometry helpers

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

func linearGradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
}

// MARK: - Drawing

func drawIcon(in context: CGContext, size: CGFloat) {
    let tileRect = CGRect(x: 0, y: 0, width: size, height: size)
    // Roughly the macOS "continuous corner" app-tile proportion.
    let tileRadius = size * 0.225
    let tilePath = roundedRectPath(tileRect, radius: tileRadius)

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    // Base gradient: light graphite top -> deep slate bottom.
    context.drawLinearGradient(
        linearGradient([Palette.tileTop, Palette.tileBottom]),
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: 0),
        options: []
    )

    // Soft top sheen for depth -- kept subtle, not a gloss slab.
    context.drawLinearGradient(
        linearGradient([Palette.tileHighlight, Palette.clear]),
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: size * 0.55),
        options: []
    )

    // Soft bottom vignette to ground the tile.
    context.drawLinearGradient(
        linearGradient([Palette.vignetteClear, Palette.tileVignette]),
        start: CGPoint(x: size / 2, y: size * 0.22),
        end: CGPoint(x: size / 2, y: 0),
        options: []
    )

    // MARK: Clipboard body
    let boardWidth = size * 0.46
    let boardHeight = size * 0.56
    let boardX = size * 0.24
    let boardY = size * 0.20
    let boardRect = CGRect(x: boardX, y: boardY, width: boardWidth, height: boardHeight)
    let boardRadius = size * 0.05
    let boardPath = roundedRectPath(boardRect, radius: boardRadius)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.02, color: Palette.boardShadow)
    context.addPath(boardPath)
    context.setFillColor(Palette.boardFill)
    context.fillPath()
    context.restoreGState()

    context.addPath(boardPath)
    context.setStrokeColor(Palette.boardStroke)
    context.setLineWidth(max(1, size * 0.004))
    context.strokePath()

    // MARK: Clip (metal tab at the top of the board)
    let clipWidth = size * 0.20
    let clipHeight = size * 0.09
    let clipX = boardX + boardWidth / 2 - clipWidth / 2
    let clipY = boardY + boardHeight - clipHeight * 0.4
    let clipRect = CGRect(x: clipX, y: clipY, width: clipWidth, height: clipHeight)
    let clipPath = roundedRectPath(clipRect, radius: clipHeight * 0.35)

    context.addPath(clipPath)
    context.setFillColor(Palette.clipFill)
    context.fillPath()
    context.addPath(clipPath)
    context.setStrokeColor(Palette.clipStroke)
    context.setLineWidth(max(1, size * 0.003))
    context.strokePath()

    // MARK: Content lines -- large sizes only, to avoid muddying small renders
    if size >= 128 {
        let lineHeight = size * 0.018
        let lineInsetX = boardX + boardWidth * 0.16
        let lineWidths: [CGFloat] = [boardWidth * 0.5, boardWidth * 0.62, boardWidth * 0.38]
        var lineY = boardY + boardHeight * 0.28
        for width in lineWidths {
            let lineRect = CGRect(x: lineInsetX, y: lineY, width: width, height: lineHeight)
            context.addPath(roundedRectPath(lineRect, radius: lineHeight / 2))
            context.setFillColor(Palette.lineColor)
            context.fillPath()
            lineY += lineHeight + size * 0.03
        }
    }

    // MARK: Lifting card -- echoes the shelf: a single card peeling off the stack
    let cardWidth = size * 0.34
    let cardHeight = size * 0.22
    let cardCenter = CGPoint(x: size * 0.635, y: size * 0.795)
    let cardAngle = -12.0 * CGFloat.pi / 180

    context.saveGState()
    context.translateBy(x: cardCenter.x, y: cardCenter.y)
    context.rotate(by: cardAngle)
    let cardRect = CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight)
    let cardRadius = size * 0.035
    let cardPath = roundedRectPath(cardRect, radius: cardRadius)

    context.saveGState()
    context.setShadow(offset: CGSize(width: size * 0.008, height: -size * 0.018), blur: size * 0.028, color: Palette.cardShadow)
    context.addPath(cardPath)
    context.setFillColor(Palette.cardFill)
    context.fillPath()
    context.restoreGState()

    context.addPath(cardPath)
    context.setStrokeColor(Palette.cardStroke)
    context.setLineWidth(max(1, size * 0.004))
    context.strokePath()
    context.restoreGState()

    context.restoreGState()
}

// MARK: - Rendering pipeline

func renderPNG(size: Int) -> Data {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create CGContext for size \(size)")
    }

    drawIcon(in: context, size: s)

    guard let cgImage = context.makeImage() else {
        fatalError("Could not create CGImage for size \(size)")
    }

    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG for size \(size)")
    }
    return data
}

// MARK: - Entry point

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let appIconSetURL = repoRoot
    .appendingPathComponent("Copy")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")

try? FileManager.default.createDirectory(at: appIconSetURL, withIntermediateDirectories: true)

let targets: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for target in targets {
    let data = renderPNG(size: target.size)
    let fileURL = appIconSetURL.appendingPathComponent("\(target.name).png")
    try data.write(to: fileURL)
    print("Wrote \(fileURL.lastPathComponent) (\(target.size)x\(target.size))")
}

print("Done. Icon assets written to \(appIconSetURL.path)")
