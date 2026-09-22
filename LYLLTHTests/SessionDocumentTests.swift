import XCTest
@testable import LYLLTH

final class SessionDocumentTests: XCTestCase {
    func testSessionPackageRoundTrip() throws {
        let source = LYLLTHSessionDocument(session: .starter())
        let wrapper = try source.packageFileWrapper(modifiedAt: source.session.modifiedAt)
        let decoded = try LYLLTHSessionDocument(fileWrapper: wrapper)

        XCTAssertEqual(decoded.session, source.session)
        XCTAssertEqual(wrapper.fileWrappers?["manifest.json"]?.isRegularFile, true)
        XCTAssertEqual(wrapper.fileWrappers?["Audio"]?.isDirectory, true)
    }
}
