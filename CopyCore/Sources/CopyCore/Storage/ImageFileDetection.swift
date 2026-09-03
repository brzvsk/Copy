import Foundation
import UniformTypeIdentifiers

/// Clipboard file items store their filenames as newline-separated `plainText`. Keep the
/// platform content-type check in one place so the Image facet can include image files
/// without broadening to every `.file` item or maintaining an extension allow-list.
enum ImageFileDetection {
    static let sqlFunctionName = "copy_contains_image_file"

    static func containsImageFile(in filenames: String) -> Bool {
        filenames.split(separator: "\n", omittingEmptySubsequences: true).contains { filename in
            let ext = (String(filename) as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
            return type.conforms(to: .image)
        }
    }
}
