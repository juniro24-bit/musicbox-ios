import SwiftUI
import UIKit

/// 커버 이미지 처리 (정사각형으로 자르기, 캐시, 대표색)
enum ImageTools {
    /// 가운데 기준 정사각형으로 잘라 600px JPEG 데이터로 돌려줘요.
    static func squareJPEG(from data: Data, side: CGFloat = 600) -> Data? {
        guard let image = UIImage(data: data), let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let s = min(w, h)
        let crop = CGRect(x: (w - s) / 2, y: (h - s) / 2, width: s, height: s)
        guard let cropped = cg.cropping(to: crop) else { return nil }
        let square = UIImage(cgImage: cropped)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let scaled = renderer.image { _ in
            square.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return scaled.jpegData(compressionQuality: 0.85)
    }

    /// 이미지 전체의 평균 색 (재생 화면 배경 빛깔에 써요)
    static func averageColor(of image: UIImage) -> Color? {
        guard let cg = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let drawn: Bool = pixel.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return Color(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255
        )
    }
}

/// 커버 이미지를 매번 디스크에서 읽지 않도록 캐시해요.
enum CoverCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for track: Track?) -> UIImage? {
        guard let track = track, let name = track.coverFileName else { return nil }
        let key = name as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let path = Paths.covers.appendingPathComponent(name).path
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func remove(name: String?) {
        guard let name = name else { return }
        cache.removeObject(forKey: name as NSString)
    }
}
