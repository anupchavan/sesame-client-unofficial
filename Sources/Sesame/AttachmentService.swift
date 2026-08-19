import Foundation
import AppKit
import UniformTypeIdentifiers

/// Upload chat media (CAS): multipart POST → storage key.
enum AttachmentService {
    static func upload(data: Data, fileName: String, mimeType: String) async throws -> String {
        let token = try await AuthManager.shared.validIDToken()
        var req = URLRequest(url: URL(string: "https://sesameai.app/api/chat-attachment")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("iOS", forHTTPHeaderField: "Client-Name")
        let boundary = "----sesame-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // The server requires mime_type and file_name as their own form fields.
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("mime_type", mimeType)
        field("file_name", fileName)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let key = json["key"] as? String else {
            throw NSError(domain: "upload", code: 2, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
        }
        return key
    }

    /// Re-encode an image to a reasonably sized JPEG for sending.
    static func jpegData(from image: NSImage, maxDimension: CGFloat = 2048) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        let scale = min(1, maxDimension / max(w, h))
        if scale >= 1 {
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
        let newSize = NSSize(width: floor(w * scale), height: floor(h * scale))
        guard let scaled = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        scaled.size = newSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return scaled.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
