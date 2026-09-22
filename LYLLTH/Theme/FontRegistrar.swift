import CoreText
import Foundation

enum FontRegistrar {
    static func registerBundledFonts() {
        let fontURLs = [nil, "Fonts"].flatMap { subdirectory in
            (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: subdirectory) ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: subdirectory) ?? [])
        }

        for url in Set(fontURLs) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
