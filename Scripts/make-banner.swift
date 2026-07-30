#!/usr/bin/env swift
// Renders the Copy banner / OG image: dark "Glass Workbench" background with the
// Duplicate mark and the wordmark + tagline. Pure Core Graphics + AppKit text.
import AppKit
import CoreGraphics
import Foundation

let W = 1200, H = 630
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("ctx")
}
func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
let bg = c(0.043, 0.047, 0.059), bg2 = c(0.063, 0.071, 0.090)
let accent = c(0.298, 0.616, 1.0), accent2 = c(0.435, 0.690, 1.0)
let text = c(0.925, 0.929, 0.945), dim = c(0.635, 0.659, 0.706)
let cardFill = c(1, 1, 1), backCard = c(0.784, 0.796, 0.824), line = c(0.729, 0.737, 0.757)

// Background gradient.
let grad = CGGradient(colorsSpace: cs, colors: [bg2, bg] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
// Top-right glow.
let glow = CGGradient(colorsSpace: cs, colors: [c(0.298, 0.616, 1.0, 0.18), c(0.298, 0.616, 1.0, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 900, y: 640), startRadius: 0,
                       endCenter: CGPoint(x: 900, y: 640), endRadius: 620, options: [])
// Faint grid.
ctx.setStrokeColor(c(0.15, 0.16, 0.19, 0.5)); ctx.setLineWidth(1)
var gx = 0; while gx <= W { ctx.move(to: CGPoint(x: CGFloat(gx), y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(gx), y: CGFloat(H))); gx += 48 }
var gy = 0; while gy <= H { ctx.move(to: CGPoint(x: 0, y: CGFloat(gy))); ctx.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(gy))); gy += 48 }
ctx.strokePath()

// The Duplicate mark (two stepped cards), right side.
func roundRect(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
let markCX: CGFloat = 900, markCY: CGFloat = 315
let cw: CGFloat = 190, ch: CGFloat = 240, crad: CGFloat = 20
// back card
let back = CGRect(x: markCX - cw/2 + 46, y: markCY - ch/2 + 44, width: cw, height: ch)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: c(0,0,0,0.5))
ctx.addPath(roundRect(back, crad)); ctx.setFillColor(backCard); ctx.fillPath(); ctx.restoreGState()
// front card
let front = CGRect(x: markCX - cw/2 - 30, y: markCY - ch/2 - 40, width: cw, height: ch)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: c(0.298,0.616,1.0,0.35))
ctx.addPath(roundRect(front, crad)); ctx.setFillColor(cardFill); ctx.fillPath(); ctx.restoreGState()
// content lines on front card
ctx.setFillColor(line)
let widths: [CGFloat] = [120, 96, 68]
var ly = front.maxY - 66
for w in widths { ctx.addPath(roundRect(CGRect(x: front.minX + 30, y: ly, width: w, height: 12), 6)); ctx.fillPath(); ly -= 30 }

// Text (left) via AppKit.
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
func draw(_ s: String, _ font: NSFont, _ color: CGColor, x: CGFloat, y: CGFloat, tracking: CGFloat = 0) {
    let col = NSColor(cgColor: color) ?? .white
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col]
    if tracking != 0 { attrs[.kern] = tracking }
    (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
}
let leftX: CGFloat = 96
draw("FREE  \u{00B7}  OPEN SOURCE  \u{00B7}  GPL-3.0",
     NSFont.monospacedSystemFont(ofSize: 20, weight: .medium), accent2, x: leftX, y: 430, tracking: 2)
draw("Copy", NSFont.systemFont(ofSize: 128, weight: .heavy), text, x: leftX - 4, y: 250)
draw("A visual shelf for everything you copy.",
     NSFont.systemFont(ofSize: 34, weight: .regular), dim, x: leftX, y: 196)
draw("Press \u{21E7}\u{2318}V. Search, pin, and paste your clipboard history.",
     NSFont.systemFont(ofSize: 22, weight: .regular), dim, x: leftX, y: 150)
NSGraphicsContext.restoreGraphicsState()

guard let img = ctx.makeImage() else { fatalError("img") }
let rep = NSBitmapImageRep(cgImage: img)
let out = "/Users/tarikbc/Programacao/Copy/docs/assets/img"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/banner.png"))
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: URL(fileURLWithPath: "\(out)/og-image.jpg"))
print("wrote banner.png + og-image.jpg")
