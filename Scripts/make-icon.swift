#!/usr/bin/env swift
//
// make-icon.swift
//
// Deterministically renders the Copy app icon: a rounded-rect app tile in a
// restrained graphite gradient, holding "The Duplicate" mark -- two stepped
// cards, a front card and its lighter copy behind it, the brand's own logo.
// Pure Core Graphics + AppKit's PNG encoder, no external assets, no randomness.
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
    // The "copy" behind the front card: a shade dimmer so it reads as a duplicate.
    static let backCardFill = CGColor(red: 0.784, green: 0.796, blue: 0.824, alpha: 1) // #C8CBD2

    static let lineColor = CGColor(red: 0.729, green: 0.737, blue: 0.757, alpha: 1)
}

// MARK: - Geometry helpers

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// A true superellipse ("squircle") boundary approximating macOS's continuous-corner
/// app-tile shape. Every sampled point satisfies |x/a|^n + |y/b|^n = 1, which is what
/// gives the tile its smoother, continuous curvature -- unlike `roundedRectPath`'s
/// circular-arc corners grafted onto straight edges, the whole outline here is one
/// continuous curve. Sampled as a fine polyline rather than analytic bezier segments
/// since this only ever needs to rasterize, not stay resolution-independent.
func superellipsePath(_ rect: CGRect, exponent n: CGFloat = 5, segments: Int = 720) -> CGPath {
    let cx = rect.midX, cy = rect.midY
    let a = rect.width / 2
    let b = rect.height / 2
    let path = CGMutablePath()
    for i in 0...segments {
        let t = CGFloat(i) / CGFloat(segments) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let x = cx + a * copysign(pow(abs(cosT), 2 / n), cosT)
        let y = cy + b * copysign(pow(abs(sinT), 2 / n), sinT)
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func linearGradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
}

// MARK: - Drawing

func drawIcon(in context: CGContext, size: CGFloat) {
    // macOS Big Sur+ icons sit inside an ~824x824 squircle centered in the
    // 1024 canvas (~9.8% transparent margin per side), or the icon renders
    // visibly larger than every native neighbor. Inset the tile rect
    // accordingly and use its side length, not the full canvas, as the local
    // scale unit for everything drawn inside it.
    let inset = size * 0.098
    let tileRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let s = tileRect.width
    // A true superellipse, not a circular-arc rounded rect -- this is what gives a
    // macOS app tile its continuous-corner "squircle" silhouette.
    let tilePath = superellipsePath(tileRect, exponent: 5)

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    // Base gradient: light graphite top -> deep slate bottom.
    context.drawLinearGradient(
        linearGradient([Palette.tileTop, Palette.tileBottom]),
        start: CGPoint(x: tileRect.midX, y: tileRect.maxY),
        end: CGPoint(x: tileRect.midX, y: tileRect.minY),
        options: []
    )

    // Soft top sheen for depth -- kept subtle, not a gloss slab.
    context.drawLinearGradient(
        linearGradient([Palette.tileHighlight, Palette.clear]),
        start: CGPoint(x: tileRect.midX, y: tileRect.maxY),
        end: CGPoint(x: tileRect.midX, y: tileRect.minY + s * 0.55),
        options: []
    )

    // Soft bottom vignette to ground the tile.
    context.drawLinearGradient(
        linearGradient([Palette.vignetteClear, Palette.tileVignette]),
        start: CGPoint(x: tileRect.midX, y: tileRect.minY + s * 0.22),
        end: CGPoint(x: tileRect.midX, y: tileRect.minY),
        options: []
    )

    // Release the squircle clip before drawing the glyph on top -- its drop
    // shadows are allowed to bleed slightly past the tile edge into the
    // transparent margin, which is how native macOS icons render.
    context.restoreGState()

    // MARK: The Duplicate -- two stepped cards, "a thing and its copy".
    let cardW = s * 0.40
    let cardH = s * 0.50
    let cardRadius = s * 0.055
    let cardLine = max(1, s * 0.004)

    // Back card (the copy): offset up and to the right, a shade dimmer so it reads
    // as the duplicate sitting behind the front one.
    let backRect = CGRect(x: tileRect.minX + s * 0.37, y: tileRect.minY + s * 0.31,
                          width: cardW, height: cardH)
    let backPath = roundedRectPath(backRect, radius: cardRadius)
    context.saveGState()
    context.setShadow(offset: CGSize(width: s * 0.006, height: -s * 0.012), blur: s * 0.022, color: Palette.cardShadow)
    context.addPath(backPath)
    context.setFillColor(Palette.backCardFill)
    context.fillPath()
    context.restoreGState()
    context.addPath(backPath)
    context.setStrokeColor(Palette.cardStroke)
    context.setLineWidth(cardLine)
    context.strokePath()

    // Front card: offset down and to the left, solid white, carrying the content.
    let frontRect = CGRect(x: tileRect.minX + s * 0.21, y: tileRect.minY + s * 0.15,
                           width: cardW, height: cardH)
    let frontPath = roundedRectPath(frontRect, radius: cardRadius)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.016), blur: s * 0.032, color: Palette.cardShadow)
    context.addPath(frontPath)
    context.setFillColor(Palette.cardFill)
    context.fillPath()
    context.restoreGState()
    context.addPath(frontPath)
    context.setStrokeColor(Palette.cardStroke)
    context.setLineWidth(cardLine)
    context.strokePath()

    // MARK: Content lines on the front card -- large sizes only, to avoid muddying
    // small renders.
    if size >= 128 {
        let lineHeight = s * 0.026
        let lineInsetX = frontRect.minX + cardW * 0.17
        let lineWidths: [CGFloat] = [cardW * 0.60, cardW * 0.48, cardW * 0.34]
        var lineY = frontRect.minY + cardH * 0.66
        for width in lineWidths {
            let lineRect = CGRect(x: lineInsetX, y: lineY, width: width, height: lineHeight)
            context.addPath(roundedRectPath(lineRect, radius: lineHeight / 2))
            context.setFillColor(Palette.lineColor)
            context.fillPath()
            lineY -= lineHeight + s * 0.05
        }
    }
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
