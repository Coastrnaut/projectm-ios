// make_app_icon.swift <input.png> <output.png>: the opaque bounding box of the input, centered on a
// 1024 x 1024 white square with a 10% margin, no alpha (App Store icons cannot be transparent).
// The app icon (Apps/projectM-iOS/Resources/Assets.xcassets/AppIcon.appiconset) was made from the
// projectM logo in the owner's fork of the UWP frontend, Coastrnaut/frontend-uwp at 82c468e,
// src/projectM-UWP/projectM-UWP.WindowsUniversal.Application/Assets/SplashScreen.png (owner decision
// 2026-11-10):  swift scripts/make_app_icon.swift SplashScreen.png AppIcon-1024.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = image.width, h = image.height
var rgba = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let read = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
read.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where rgba[(y * w + x) * 4 + 3] > 16 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
// Bitmap rows run top-down here; CGImage cropping uses the same top-left origin.
let crop = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
let size = 1024
let out = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
out.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
out.fill(CGRect(x: 0, y: 0, width: size, height: size))
out.interpolationQuality = .high
let box = Double(size) * 0.8
let scale = min(box / Double(crop.width), box / Double(crop.height))
let dw = Double(crop.width) * scale, dh = Double(crop.height) * scale
out.draw(crop, in: CGRect(x: (Double(size) - dw) / 2, y: (Double(size) - dh) / 2, width: dw, height: dh))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("crop \(crop.width)x\(crop.height) -> \(Int(dw))x\(Int(dh)) on \(size)x\(size)")
