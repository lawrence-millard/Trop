//
//  LibraryContinuationTests.swift
//  TropTests
//
//  Library playlists/albums use grid items; artists use a music shelf.
//  Both page through continuationItemRenderer + appendContinuationItemsAction,
//  and the older continuationContents shape still parses.
//

import XCTest
@testable import Trop

final class LibraryContinuationTests: XCTestCase {
    func testGridPagesYieldEveryItemAndFollowTokensUntilNoneRemain() throws {
        let page1 = try loadLibraryFixture("library-grid-page1")
        let page2 = try loadLibraryFixture("library-grid-page2-append")
        let page3 = try loadLibraryFixture("library-grid-page3-append")

        XCTAssertEqual(markers(in: LibraryBrowseParser.extractItems(from: page1)), ["grid-01", "grid-02"])
        XCTAssertEqual(LibraryBrowseParser.extractContinuationToken(from: page1), "grid-tok-2")
        XCTAssertEqual(markers(in: LibraryBrowseParser.extractItems(from: page2)), ["grid-03"])
        XCTAssertEqual(LibraryBrowseParser.extractContinuationToken(from: page2), "grid-tok-3")
        XCTAssertEqual(markers(in: LibraryBrowseParser.extractItems(from: page3)), ["grid-04"])
        XCTAssertNil(LibraryBrowseParser.extractContinuationToken(from: page3))

        let walk = walkLibrary(
            first: page1,
            pagesByToken: ["grid-tok-2": page2, "grid-tok-3": page3]
        )
        XCTAssertEqual(walk.markers, ["grid-01", "grid-02", "grid-03", "grid-04"])
        XCTAssertEqual(walk.tokensFollowed, ["grid-tok-2", "grid-tok-3"])
        XCTAssertNil(walk.unfollowedToken)
    }

    func testArtistShelfContinuationItemToken() throws {
        let page = try loadLibraryFixture("library-shelf-page1")
        XCTAssertEqual(markers(in: LibraryBrowseParser.extractItems(from: page)), ["artist-01"])
        XCTAssertEqual(LibraryBrowseParser.extractContinuationToken(from: page), "shelf-tok-2")
        let items = try XCTUnwrap(LibraryBrowseParser.extractItems(from: page))
        XCTAssertFalse(items.contains { $0["continuationItemRenderer"] != nil })
    }

    func testLegacyGridContinuationStillParses() throws {
        let page = try loadLibraryFixture("library-legacy-grid-page2")
        XCTAssertEqual(markers(in: LibraryBrowseParser.extractItems(from: page)), ["legacy-grid-02"])
        XCTAssertEqual(LibraryBrowseParser.extractContinuationToken(from: page), "legacy-grid-tok-2")
    }

    func testLegacyShelfTokenStillWins() {
        let page: [String: Any] = [
            "contents": [
                "singleColumnBrowseResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [[
                                        "musicShelfRenderer": [
                                            "contents": [
                                                ["marker": "shelf-legacy", "musicResponsiveListItemRenderer": [:]]
                                            ],
                                            "continuations": [[
                                                "nextContinuationData": ["continuation": "shelf-legacy-tok"]
                                            ]]
                                        ]
                                    ]]
                                ]
                            ]
                        ]
                    ]]
                ]
            ]
        ]
        XCTAssertEqual(markers(in: LibraryBrowseParser.extractItems(from: page)), ["shelf-legacy"])
        XCTAssertEqual(LibraryBrowseParser.extractContinuationToken(from: page), "shelf-legacy-tok")
    }

    func testLibraryPageCapStopsBeforeTheNextToken() throws {
        let page1 = try loadLibraryFixture("library-grid-page1")
        let page2 = try loadLibraryFixture("library-grid-page2-append")
        let walk = walkLibrary(
            first: page1,
            pagesByToken: ["grid-tok-2": page2],
            maxPages: 1
        )
        XCTAssertEqual(walk.markers, ["grid-01", "grid-02"])
        XCTAssertEqual(walk.tokensFollowed, [])
        XCTAssertEqual(walk.stop, .pageCap)
    }
}

private struct LibraryWalk {
    var markers: [String]
    var tokensFollowed: [String]
    var unfollowedToken: String?
    var stop: ContinuationItems.Stop?
}

private func walkLibrary(
    first: [String: Any],
    pagesByToken: [String: [String: Any]],
    maxPages: Int = 50
) -> LibraryWalk {
    var current: [String: Any]? = first
    var requestToken: String?
    var seenTokens = Set<String>()
    var pages = 0
    var markersFound: [String] = []
    var followed: [String] = []
    while let page = current {
        if let requestToken {
            followed.append(requestToken)
        }
        if let items = LibraryBrowseParser.extractItems(from: page) {
            markersFound.append(contentsOf: markers(in: items))
        }
        let token = LibraryBrowseParser.extractContinuationToken(from: page)
        pages += 1
        if let reason = ContinuationItems.stopReason(
            token: token,
            seenTokens: &seenTokens,
            pages: pages,
            maxPages: maxPages
        ) {
            return LibraryWalk(
                markers: markersFound,
                tokensFollowed: followed,
                unfollowedToken: token,
                stop: reason
            )
        }
        guard let token else {
            return LibraryWalk(
                markers: markersFound,
                tokensFollowed: followed,
                unfollowedToken: nil,
                stop: nil
            )
        }
        requestToken = token
        current = pagesByToken[token]
    }
    return LibraryWalk(
        markers: markersFound,
        tokensFollowed: followed,
        unfollowedToken: requestToken,
        stop: nil
    )
}

private func markers(in rows: [[String: Any]]?) -> [String] {
    (rows ?? []).compactMap { $0["marker"] as? String }
}

private func loadLibraryFixture(_ name: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("\(name).json")
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let json = object as? [String: Any] else {
        throw NSError(domain: "TropTests", code: 1)
    }
    return json
}
