#!/usr/bin/env swift
// Renders the Copy DMG background (660x470) in a light "Glass Workbench" treatment:
// a soft light gradient, a faint blueprint grid, the Duplicate logo mark and the "Copy"
// wordmark up top, an electric-blue drag arrow between the app icon and the Applications
// folder (both drawn by Finder via dmg_settings.py), and a one-line install instruction
// along the bottom. Pure Core Graphics + AppKit text, so it renders headlessly.
//
// Why light, not dark: Finder draws the icon *labels* ("Copy"/"Applications") in black
// when the user's Mac is in Light Mode, and black-on-dark is unreadable. A light ground
// keeps those labels legible in both Light and Dark appearances (this is why CamLoop's
// DMG is light too). Copy's brand is adaptive, so this is simply its light side.
//
// This is a generator, run by hand when the design changes; the release pipeline
// consumes the committed Scripts/dmg-background.png. Usage:
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
let bgTop = c(0.902, 0.918, 0.941)      // cooler light at the top
let bgBottom = c(0.984, 0.988, 0.992)   // near-white, lighter toward the bottom
let accent = c(0.184, 0.498, 0.878)     // #2F7FE0 — the deeper blue reads on a light ground
let ink = c(0.086, 0.094, 0.114)        // wordmark
let dim = c(0.376, 0.404, 0.451)        // tagline + instruction

// Background gradient: a touch cooler/darker at the top, lightening to near-white at the
// bottom (keeps some depth without ever getting dark enough to fight the black labels).
let grad = CGGradient(colorsSpace: cs, colors: [bgBottom, bgTop] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
// Faint accent wash in the top-right for a hint of brand, kept very subtle on light.
let glow = CGGradient(colorsSpace: cs, colors: [c(0.184, 0.498, 0.878, 0.10), c(0.184, 0.498, 0.878, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 560, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 560, y: 470), endRadius: 460, options: [])
// Faint blueprint grid.
ctx.setStrokeColor(c(0.09, 0.13, 0.22, 0.05)); ctx.setLineWidth(1)
var gx = 0; while gx <= W { ctx.move(to: CGPoint(x: CGFloat(gx), y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(gx), y: CGFloat(H))); gx += 44 }
var gy = 0; while gy <= H { ctx.move(to: CGPoint(x: 0, y: CGFloat(gy))); ctx.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(gy))); gy += 44 }
ctx.strokePath()

// Logo mark: the "Duplicate" (two stepped cards), centered above the wordmark. On a light
// ground the white front card gets a hairline border so it separates from the background.
func roundRect(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
let markCX: CGFloat = CGFloat(W) / 2, markCY: CGFloat = 420
let mcw: CGFloat = 46, mch: CGFloat = 58, mrad: CGFloat = 9
let backCard = c(0.796, 0.812, 0.843), cardFill = c(1, 1, 1)
let cardStroke = c(0.796, 0.812, 0.843), lineCol = c(0.686, 0.706, 0.741)
// Back card, up and to the right, with a soft neutral shadow.
let backRect = CGRect(x: markCX - mcw / 2 + 11, y: markCY - mch / 2 + 11, width: mcw, height: mch)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 9, color: c(0.2, 0.24, 0.32, 0.35))
ctx.addPath(roundRect(backRect, mrad)); ctx.setFillColor(backCard); ctx.fillPath(); ctx.restoreGState()
// Front card, down and to the left, lifted with a soft shadow and a hairline border.
let frontRect = CGRect(x: markCX - mcw / 2 - 9, y: markCY - mch / 2 - 10, width: mcw, height: mch)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 13, color: c(0.2, 0.24, 0.32, 0.28))
ctx.addPath(roundRect(frontRect, mrad)); ctx.setFillColor(cardFill); ctx.fillPath(); ctx.restoreGState()
ctx.addPath(roundRect(frontRect, mrad)); ctx.setStrokeColor(cardStroke); ctx.setLineWidth(1); ctx.strokePath()
// Content lines on the front card.
ctx.setFillColor(lineCol)
let markLineWidths: [CGFloat] = [28, 22, 15]
var mly = frontRect.maxY - 15
for w in markLineWidths { ctx.addPath(roundRect(CGRect(x: frontRect.minX + 9, y: mly, width: w, height: 4), 2)); ctx.fillPath(); mly -= 9 }

// Text (wordmark, tagline, instruction) via AppKit, centered.
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
func drawCentered(_ s: String, _ font: NSFont, _ color: CGColor, y: CGFloat, tracking: CGFloat = 0) {
    let col = NSColor(cgColor: color) ?? .black
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col]
    if tracking != 0 { attrs[.kern] = tracking }
    let size = (s as NSString).size(withAttributes: attrs)
    (s as NSString).draw(at: CGPoint(x: (CGFloat(W) - size.width) / 2, y: y), withAttributes: attrs)
}
drawCentered("Copy", NSFont.systemFont(ofSize: 44, weight: .heavy), ink, y: 334)
drawCentered("A visual shelf for everything you copy", NSFont.systemFont(ofSize: 14, weight: .regular), dim, y: 310)
drawCentered("Drag Copy onto the Applications folder to install",
             NSFont.systemFont(ofSize: 13, weight: .regular), dim, y: 60)
NSGraphicsContext.restoreGraphicsState()

// Electric-blue drag arrow between the app icon (~x165) and Applications (~x495),
// at the icon row (dmgbuild centers both icons at y=250 top-left -> y=220 in AppKit).
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
