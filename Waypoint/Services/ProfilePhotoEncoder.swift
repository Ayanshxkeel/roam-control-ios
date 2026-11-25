import UIKit

@MainActor enum ProfilePhotoEncoder {
    static func encode(_ data: Data) throws -> String {
        guard data.count <= 25_000_000, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format)
        let thumbnail = renderer.image { context in
            UIColor.systemBackground.setFill(); context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            let scale = max(128 / image.size.width, 128 / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (128-size.width)/2, y: (128-size.height)/2, width: size.width, height: size.height))
        }
        guard let jpeg = thumbnail.jpegData(compressionQuality: 0.65), jpeg.count <= 60_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        return jpeg.base64EncodedString()
    }
}
