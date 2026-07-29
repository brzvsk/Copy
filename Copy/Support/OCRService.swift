import Foundation
import ImageIO
import Vision

/// Recognizes text in copied images entirely on-device via Vision. No network access
/// is ever used — recognition runs against the local `CGImage` only.
enum OCRService {
    /// Recognizes text in `imageData` (PNG or TIFF) and calls `completion` with the
    /// joined recognized lines, or `nil` if no text was found or recognition failed.
    /// Always hops off the calling thread, so callers never need their own dispatch.
    static func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                completion(nil)
                return
            }

            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation]
                else {
                    completion(nil)
                    return
                }
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                completion(text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                completion(nil)
            }
        }
    }
}
