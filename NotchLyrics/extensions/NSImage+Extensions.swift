//
//  Image2Color.swift
//  Notch Lyrics
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI
import AppKit
import Cocoa
import Foundation
import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins

extension NSImage {

    
    func averageColor(completion: @escaping (NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let width = cgImage.width
            let height = cgImage.height
            let totalPixels = width * height
            
            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            guard let data = context.data else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)
            
            var totalRed: UInt64 = 0
            var totalGreen: UInt64 = 0
            var totalBlue: UInt64 = 0
            
            for i in 0..<totalPixels {
                let color = pointer[i]
                totalRed += UInt64(color & 0xFF)
                totalGreen += UInt64((color >> 8) & 0xFF)
                totalBlue += UInt64((color >> 16) & 0xFF)
            }
            
            let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
            let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
            let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
            
            let minBrightness: CGFloat = 0.5
            let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03
            
            var finalColor: NSColor
            
            if isNearBlack {
                // If it's near black, just return a gray color with the minimum brightness
                finalColor = NSColor(white: minBrightness, alpha: 1.0)
            } else {
                var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
                
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                
                if brightness < minBrightness {
                    // Increase brightness while maintaining hue and reducing saturation
                    let saturationScale = brightness / minBrightness
                    color = NSColor(hue: hue,
                                    saturation: saturation * saturationScale,
                                    brightness: minBrightness,
                                    alpha: alpha)
                }
                
                finalColor = color
            }
            
            DispatchQueue.main.async {
                completion(finalColor)
            }
        }
        
    }
    
    func getBrightness() -> CGFloat {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }
        
        let inputImage = CIImage(cgImage: cgImage)
        
        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = inputImage.extent
        
        guard let outputImage = filter.outputImage else {
            return 0
        }
        
        let context = CIContext(options: nil)
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let brightness = (0.2126 * CGFloat(bitmap[0]) + 0.7152 * CGFloat(bitmap[1]) + 0.0722 * CGFloat(bitmap[2])) / 255.0
        
        return brightness
    }
}

extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        guard factor >= 0 && factor <= 1 else {
            return self // Return original color if factor is out of bounds
        }
        
        let nsColor = NSColor(self)
        
        // Convert to RGB color space
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return self // Return original color if conversion fails
        }
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Calculate perceived brightness using the formula: (0.299*R + 0.587*G + 0.114*B)
        let perceivedBrightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue)
        
        let scale = factor / perceivedBrightness
        red = min(red * scale, 1.0)
        green = min(green * scale, 1.0)
        blue = min(blue * scale, 1.0)
        
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }

    /// Album-art tint used as *text* ink on the notch slab.
    ///
    /// The slab measures roughly sRGB (92, 91, 91), i.e. relative luminance ≈ 0.10.
    /// A saturated cover colour scaled to brightness 0.9 still measured only
    /// 3.11:1 there — short of the 4.5:1 needed for 12pt text. Raising brightness
    /// alone cannot fix it: a saturated hue has a luminance ceiling, and pushing
    /// it harder just drifts toward white anyway.
    ///
    /// So blend toward white by the *smallest* amount that clears the contrast
    /// target. Binary search keeps as much of the cover hue as legibility allows.
    /// 4.8 (rather than 4.5) leaves headroom for antialiasing and for the slab
    /// brightening on light wallpapers: a 4.5 target measured only 4.38:1 on screen.
    func slabLegibleInk(minimumContrast: CGFloat = 4.8) -> Color {
        let slabLuminance: CGFloat = 0.11
        let required = minimumContrast * (slabLuminance + 0.05) - 0.05
        guard required <= 1,
              let tint = NSColor(self).usingColorSpace(.sRGB),
              let white = NSColor.white.usingColorSpace(.sRGB) else { return self }

        func decode(_ v: CGFloat) -> CGFloat {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        func luminance(_ c: NSColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.2126 * decode(r) + 0.7152 * decode(g) + 0.0722 * decode(b)
        }
        // blended(withFraction:of:) weights the *other* colour, so the tint
        // weight is 1 - whiteFraction.
        func mixed(_ whiteFraction: CGFloat) -> NSColor {
            white.blended(withFraction: 1 - whiteFraction, of: tint) ?? white
        }

        if luminance(tint) >= required { return self }
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            if luminance(mixed(mid)) < required { lo = mid } else { hi = mid }
        }
        return Color(nsColor: mixed(hi))
    }
}

// MARK: - 封面色板

extension NSImage {

    /// 从封面里取 2–3 个"主要色系",供刘海的散光使用。
    ///
    /// 不能用平均色:平均会把封面里的粉和黑混成一团脏紫,永远出不来
    /// "封面带粉、光就带粉"的效果。这里的做法是缩小采样后按色相分桶:
    /// 权重 = 饱和度 ×(亮度贴近中间的程度),黑边、白字、灰底不带色相,
    /// 不参与;相邻色相(±1 桶,含首尾回绕)视为同一色系,取权重最高的几桶。
    ///
    /// 黑白封面提取不到色板,返回空数组 —— 没有可散的"色",散光就该缺席。
    func dominantColors(count: Int = 3, completion: @escaping ([NSColor]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let colours = Self.extractDominantColours(from: self, count: count)
            DispatchQueue.main.async { completion(colours) }
        }
    }

    private static func extractDominantColours(from image: NSImage, count: Int) -> [NSColor] {
        // 24×24 足够读出色系,再大也只是更慢。
        let size = 24
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return [] }
        let pointer = data.bindMemory(to: UInt32.self, capacity: size * size)

        var buckets: [Int: (weight: Double, r: Double, g: Double, b: Double, n: Double)] = [:]
        for index in 0..<(size * size) {
            let pixel = pointer[index]
            // 布局与 averageColor 一致:低字节是红。
            let r = Double(pixel & 0xFF) / 255
            let g = Double((pixel >> 8) & 0xFF) / 255
            let b = Double((pixel >> 16) & 0xFF) / 255
            guard Double(pixel >> 24 & 0xFF) / 255 > 0.5 else { continue }

            let colour = NSColor(red: r, green: g, blue: b, alpha: 1)
            let hue = Double(colour.hueComponent)
            let saturation = Double(colour.saturationComponent)
            let brightness = Double(colour.brightnessComponent)
            guard saturation > 0.15, brightness > 0.12, brightness < 0.95 else { continue }

            let bucket = Int(hue * 12) % 12
            let weight = pow(saturation, 1.4) * (1 - abs(brightness - 0.55) * 0.8)
            var slot = buckets[bucket, default: (0, 0, 0, 0, 0)]
            slot.weight += weight
            slot.r += r * weight
            slot.g += g * weight
            slot.b += b * weight
            slot.n += weight
            buckets[bucket] = slot
        }

        var chosen: [(bucket: Int, colour: NSColor)] = []
        for (bucket, slot) in buckets.sorted(by: { $0.value.weight > $1.value.weight }) {
            guard chosen.count < count else { break }
            let distance = { (lhs: Int, rhs: Int) -> Int in
                let raw = abs(lhs - rhs)
                return min(raw, 12 - raw)
            }
            // 相邻色相视为同一色系,保证拿回来的是"不同的几个色系"。
            if chosen.contains(where: { distance($0.bucket, bucket) <= 1 }) { continue }

            let n = max(slot.n, 0.0001)
            chosen.append((bucket, NSColor(
                red: min(max(slot.r / n, 0), 1),
                green: min(max(slot.g / n, 0), 1),
                blue: min(max(slot.b / n, 0), 1),
                alpha: 1)))
        }
        return chosen.map(\.colour)
    }
}
