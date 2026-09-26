import CoreText
import Foundation

enum FontRegistrar {
    static func registerBundledFonts(in bundle: Bundle = .main) {
        let fontURLs = [nil, "Fonts"].flatMap { subdirectory in
            (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: subdirectory) ?? [])
                + (bundle.urls(forResourcesWithExtension: "otf", subdirectory: subdirectory) ?? [])
        }

        for url in Set(fontURLs) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
