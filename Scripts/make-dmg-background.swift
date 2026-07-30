#!/usr/bin/env swift
// Renders the Copy DMG background (660x400) in the "Glass Workbench" style, matching
// the banner/site: dark gradient, a faint blueprint grid + a soft top-right glow, the
// "Copy" wordmark and a short tagline up top, an electric-blue drag arrow between the
// app icon and the Applications folder (both drawn by Finder via dmg_settings.py), and
// a one-line install instruction along the bottom. Pure Core Graphics + AppKit text, so
// it renders headlessly.
//
// This is a generator, run by hand when the design changes; the release pipeline
// consumes the committed Scripts/dmg-background.png (mirrors make-banner.swift ->
// docs/assets/img/banner.png). Usage:
//   swift Scripts/make-dmg-background.swift Scripts/dmg-background.png
import AppKit
import CoreGraphics
import Foundation

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/dmg-background.png"

let W = 660, H = 470
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("ctx")
}
func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
let bgTop = c(0.043, 0.047, 0.059)      // darkest, at the top behind the wordmark
let bgBottom = c(0.102, 0.114, 0.145)   // lighter, at the bottom so the instruction reads
let accent = c(0.298, 0.616, 1.0)
let text = c(0.925, 0.929, 0.945), dim = c(0.722, 0.741, 0.784)

// Background gradient: dark at the top (the large white wordmark stands out on it),
// lighter toward the bottom so the smaller tagline/instruction text stays legible.
let grad = CGGradient(colorsSpace: cs, colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
// Soft accent glow lifted toward the bottom (mirrors the old top glow), broad enough
// to light the whole lower band under the icons and instruction.
let glow = CGGradient(colorsSpace: cs, colors: [c(0.298, 0.616, 1.0, 0.15), c(0.298, 0.616, 1.0, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 440, y: -60), startRadius: 0,
                       endCenter: CGPoint(x: 440, y: -60), endRadius: 540, options: [])
// Faint blueprint grid.
ctx.setStrokeColor(c(0.15, 0.16, 0.19, 0.5)); ctx.setLineWidth(1)
var gx = 0; while gx <= W { ctx.move(to: CGPoint(x: CGFloat(gx), y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(gx), y: CGFloat(H))); gx += 44 }
var gy = 0; while gy <= H { ctx.move(to: CGPoint(x: 0, y: CGFloat(gy))); ctx.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(gy))); gy += 44 }
ctx.strokePath()

// Logo mark: the "Duplicate" (two stepped cards, white front over a grey back),
// centered above the wordmark. Mirrors the app icon and banner mark.
func roundRect(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
let markCX: CGFloat = CGFloat(W) / 2, markCY: CGFloat = 420
let mcw: CGFloat = 46, mch: CGFloat = 58, mrad: CGFloat = 9
let backCard = c(0.784, 0.796, 0.824), cardFill = c(1, 1, 1), lineCol = c(0.729, 0.737, 0.757)
// Back card, up and to the right, with a soft dark shadow.
let backRect = CGRect(x: markCX - mcw / 2 + 11, y: markCY - mch / 2 + 11, width: mcw, height: mch)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 9, color: c(0, 0, 0, 0.5))
ctx.addPath(roundRect(backRect, mrad)); ctx.setFillColor(backCard); ctx.fillPath(); ctx.restoreGState()
// Front card, down and to the left, lifted with a faint accent shadow.
let frontRect = CGRect(x: markCX - mcw / 2 - 9, y: markCY - mch / 2 - 10, width: mcw, height: mch)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 13, color: c(0.298, 0.616, 1.0, 0.4))
ctx.addPath(roundRect(frontRect, mrad)); ctx.setFillColor(cardFill); ctx.fillPath(); ctx.restoreGState()
// Content lines on the front card.
ctx.setFillColor(lineCol)
let markLineWidths: [CGFloat] = [28, 22, 15]
var mly = frontRect.maxY - 15
for w in markLineWidths { ctx.addPath(roundRect(CGRect(x: frontRect.minX + 9, y: mly, width: w, height: 4), 2)); ctx.fillPath(); mly -= 9 }

// Text (wordmark, tagline, instruction) via AppKit, centered.
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
func drawCentered(_ s: String, _ font: NSFont, _ color: CGColor, y: CGFloat, tracking: CGFloat = 0) {
    let col = NSColor(cgColor: color) ?? .white
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col]
    if tracking != 0 { attrs[.kern] = tracking }
    let size = (s as NSString).size(withAttributes: attrs)
    (s as NSString).draw(at: CGPoint(x: (CGFloat(W) - size.width) / 2, y: y), withAttributes: attrs)
}
drawCentered("Copy", NSFont.systemFont(ofSize: 44, weight: .heavy), text, y: 334)
drawCentered("A visual shelf for everything you copy", NSFont.systemFont(ofSize: 14, weight: .regular), dim, y: 310)
drawCentered("Drag Copy onto the Applications folder to install",
             NSFont.systemFont(ofSize: 13, weight: .regular), dim, y: 58)
NSGraphicsContext.restoreGraphicsState()

// Electric-blue drag arrow between the app icon (~x165) and Applications (~x495),
// at the icon row (dmgbuild centers both icons at y=180 top-left -> y=220 in AppKit).
let ay: CGFloat = 220
ctx.setStrokeColor(accent); ctx.setLineWidth(4); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 264, y: ay)); ctx.addLine(to: CGPoint(x: 398, y: ay)); ctx.strokePath()
ctx.setFillColor(accent)
ctx.move(to: CGPoint(x: 410, y: ay))
ctx.addLine(to: CGPoint(x: 390, y: ay + 11))
ctx.addLine(to: CGPoint(x: 390, y: ay - 11))
ctx.closePath(); ctx.fillPath()

guard let img = ctx.makeImage() else { fatalError("img") }
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
