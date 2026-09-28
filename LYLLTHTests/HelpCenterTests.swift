import XCTest
@testable import LYLLTH

final class HelpCenterTests: XCTestCase {
    func testLibraryHasDepthAndEveryCategoryIsCovered() {
        XCTAssertGreaterThanOrEqual(LYHelpLibrary.articles.count, 35)
        for category in LYHelpCategory.allCases {
            XCTAssertTrue(
                LYHelpLibrary.articles.contains { $0.category == category },
                "No help article covers \(category.rawValue)"
            )
        }
    }

    func testArticleAndSectionIdentifiersAreUnique() {
        let articleIDs = LYHelpLibrary.articles.map(\.id)
        XCTAssertEqual(Set(articleIDs).count, articleIDs.count)

        for article in LYHelpLibrary.articles {
            let sectionIDs = article.sections.map(\.id)
            XCTAssertEqual(Set(sectionIDs).count, sectionIDs.count, "Duplicate section in \(article.id)")
        }
    }

    func testEveryRelatedArticleExists() {
        let knownIDs = Set(LYHelpLibrary.articles.map(\.id))
        for article in LYHelpLibrary.articles {
            for relatedID in article.related {
                XCTAssertTrue(knownIDs.contains(relatedID), "\(article.id) links to missing \(relatedID)")
                XCTAssertNotEqual(article.id, relatedID)
            }
        }
    }

    func testTaskAndSymptomSearchesReachTheRightPage() {
        XCTAssertEqual(LYHelpLibrary.search("punch").first?.id, "punch-takes")
        XCTAssertTrue(LYHelpLibrary.search("record vocals").contains { $0.id == "record-audio" })
        XCTAssertTrue(LYHelpLibrary.search("missing audio").contains { $0.id == "missing-media" })
        XCTAssertTrue(LYHelpLibrary.search("late take").contains { $0.id == "recording-problems" })
        XCTAssertEqual(LYHelpLibrary.search("keyboard shortcuts").first?.id, "shortcuts")
    }

    func testHelpCopyAvoidsPlaceholderAndGeneratedSoundingLanguage() {
        let copy = LYHelpLibrary.articles.map(\.searchableText).joined(separator: " ")
        let rejected = [
            "lorem ipsum", "comprehensive guide", "seamlessly", "leverage", "robust solution",
            "delve into", "in conclusion", "whether you're", "game-changing", "unlock your"
        ]
        for phrase in rejected {
            XCTAssertFalse(copy.contains(phrase), "Help copy contains rejected phrase: \(phrase)")
        }
    }
}
