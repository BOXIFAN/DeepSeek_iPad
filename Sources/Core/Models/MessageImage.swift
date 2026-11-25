import Foundation
import UIKit

// MARK: - 图片附件

/// 一条用户消息里带的图片。落库时直接进协议块（base64），不做压缩二次存储。
struct MessageImage: Identifiable, Equatable, Sendable {
    let id: UUID
    /// 压缩后的 JPEG 数据
    var data: Data
    var mediaType: String
    /// 压缩后的像素尺寸，用于气泡等比展示
    var width: CGFloat
    var height: CGFloat

    var uiImage: UIImage? { UIImage(data: data) }

    /// Anthropic 格式的图片块。
    var blockJSON: [String: Any] {
        [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": mediaType,
                "data": data.base64EncodedString()
            ]
        ]
    }

    /// 从历史消息的原始块里还原。
    static func decode(from block: [String: Any]) -> MessageImage? {
        guard block["type"] as? String == "image",
              let source = block["source"] as? [String: Any],
              source["type"] as? String == "base64",
              let mediaType = source["media_type"] as? String,
              let base64 = source["data"] as? String,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else {
            return nil
        }
        return MessageImage(
            id: UUID(),
            data: data,
            mediaType: mediaType,
            width: image.size.width,
            height: image.size.height
        )
    }

    static func == (lhs: MessageImage, rhs: MessageImage) -> Bool {
        lhs.id == rhs.id && lhs.data == rhs.data
    }
}

// MARK: - 压缩

/// 服务端会把每张图缩到约 1300×1300 再计费（上限 1024 token），
/// 客户端先压到 1280 长边、JPEG 0.75，请求体小一半以上。
enum ImagePipeline {

    static let maxDimension: CGFloat = 1280
    static let jpegQuality: CGFloat = 0.75
    /// 单条消息最多几张
    static let maxCount = 4

    static func make(from data: Data) -> MessageImage? {
        guard let image = UIImage(data: data) else { return nil }
        let scaled = downsample(image)
        guard let jpeg = scaled.jpegData(compressionQuality: jpegQuality) else { return nil }
        return MessageImage(
            id: UUID(),
            data: jpeg,
            mediaType: "image/jpeg",
            width: scaled.size.width,
            height: scaled.size.height
        )
    }

    static func downsample(_ image: UIImage) -> UIImage {
        let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width))
        let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height))
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let target = CGSize(width: (pixelWidth * scale).rounded(),
                            height: (pixelHeight * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
