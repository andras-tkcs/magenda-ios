import AppCore
import CoreText
import Foundation

/// Why the rendering resources could not be loaded.
enum FontLibraryError: Error, Equatable {
    /// A bundled font file is absent or is not a usable font; the text is the file name.
    case missingFont(String)
    /// The template PDF is absent or cannot be read.
    case missingTemplate
}

/// The 15 bundled fonts, loaded once from font files and never registered system-wide.
// Immutable after `init`, and CoreText font descriptors are thread-safe, so sharing is safe even
// though the compiler cannot see it.
final class FontLibrary: @unchecked Sendable {
    private let descriptors: [String: CTFontDescriptor]

    /// Loads every pack and weight from `bundle`; throws `missingFont` for the first one that is
    /// absent or unreadable.
    init(bundle: Bundle) throws {
        var loaded: [String: CTFontDescriptor] = [:]
        for pack in FontPack.allCases {
            for weight in FontWeight.allCases {
                let name = pack.fontFileName(weight)
                guard let url = bundle.url(forResource: name, withExtension: "ttf"),
                    let data = try? Data(contentsOf: url),
                    let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData)
                else {
                    throw FontLibraryError.missingFont(name)
                }
                loaded[name] = descriptor
            }
        }
        descriptors = loaded
    }

    /// The font for `spec`, at its (already scaled) size.
    func font(_ spec: FontSpec) -> CTFont {
        let name = spec.pack.fontFileName(spec.weight)
        guard let descriptor = descriptors[name] else {
            return CTFontCreateWithName("Helvetica" as CFString, spec.size, nil)
        }
        return CTFontCreateWithFontDescriptor(descriptor, spec.size, nil)
    }
}
