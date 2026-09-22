import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let lyllthSession = UTType(exportedAs: "net.nightshape.lyllth.session", conformingTo: .package)
}

private struct LYLLTHManifest: Codable {
    var format = "lyllth"
    var schemaVersion: Int
    var generatedBy = "LYLLTH macOS"
    var projectFileName = "project.json"
    var projectID: UUID
    var projectName: String
    var modifiedAt: Date
}

struct LYLLTHSessionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.lyllthSession] }
    static var writableContentTypes: [UTType] { [.lyllthSession] }

    var session: LYLLTHSession

    init(session: LYLLTHSession = .starter()) {
        self.session = session
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file)
    }

    init(fileWrapper: FileWrapper) throws {
        guard fileWrapper.isDirectory,
              let children = fileWrapper.fileWrappers,
              let projectData = children["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LYLLTHSession.self, from: projectData)
        guard decoded.schemaVersion <= LYLLTHSession.currentSchemaVersion else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        session = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try packageFileWrapper()
    }

    func packageFileWrapper(modifiedAt: Date = Date()) throws -> FileWrapper {
        var snapshot = session
        snapshot.modifiedAt = modifiedAt

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let manifest = LYLLTHManifest(
            schemaVersion: LYLLTHSession.currentSchemaVersion,
            projectID: snapshot.id,
            projectName: snapshot.name,
            modifiedAt: snapshot.modifiedAt
        )

        return FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: try encoder.encode(manifest)),
            "project.json": FileWrapper(regularFileWithContents: try encoder.encode(snapshot)),
            "Audio": FileWrapper(directoryWithFileWrappers: [:]),
            "Presets": FileWrapper(directoryWithFileWrappers: [:]),
            "PluginStates": FileWrapper(directoryWithFileWrappers: [:])
        ])
    }
}
