//
//  PlaylistContinuationTests.swift
//  TropTests
//
//  Page 1 shelf + continuationItemRenderer, then appendContinuationItemsAction
//  pages, plus the older continuationContents shape.
//

import XCTest
@testable import Trop

final class PlaylistContinuationTests: XCTestCase {
    func testModernPagesYieldEveryRowAndFollowTokensUntilNoneRemain() throws {
        let page1 = try loadFixture("playlist-page1-shelf")
        let page2 = try loadFixture("playlist-page2-append")
        let page3 = try loadFixture("playlist-page3-append")

        let page1Items = try XCTUnwrap(PlaylistBrowseParser.extractItems(from: page1))
        XCTAssertEqual(videoIDs(in: page1Items), ["song-01", "song-02"])
        XCTAssertFalse(page1Items.contains { $0["continuationItemRenderer"] != nil })
        XCTAssertEqual(PlaylistBrowseParser.extractContinuation(from: page1), "tok-2")

        let page2Items = try XCTUnwrap(PlaylistBrowseParser.extractItems(from: page2))
        XCTAssertEqual(videoIDs(in: page2Items), ["song-03", "song-04"])
        XCTAssertEqual(PlaylistBrowseParser.extractContinuation(from: page2), "tok-3")

        let page3Items = try XCTUnwrap(PlaylistBrowseParser.extractItems(from: page3))
        XCTAssertEqual(videoIDs(in: page3Items), ["song-05"])
        XCTAssertNil(PlaylistBrowseParser.extractContinuation(from: page3))

        let walk = walkPlaylist(
            first: page1,
            pagesByToken: ["tok-2": page2, "tok-3": page3]
        )
        XCTAssertEqual(walk.ids, ["song-01", "song-02", "song-03", "song-04", "song-05"])
        XCTAssertEqual(walk.tokensFollowed, ["tok-2", "tok-3"])
        XCTAssertNil(walk.unfollowedToken)
    }

    func testLegacyContinuationContentsStillParses() throws {
        let page1 = try loadFixture("playlist-legacy-page1")
        let page2 = try loadFixture("playlist-legacy-page2")

        XCTAssertEqual(videoIDs(in: try XCTUnwrap(PlaylistBrowseParser.extractItems(from: page1))), ["legacy-01"])
        XCTAssertEqual(PlaylistBrowseParser.extractContinuation(from: page1), "legacy-tok")
        XCTAssertEqual(videoIDs(in: try XCTUnwrap(PlaylistBrowseParser.extractItems(from: page2))), ["legacy-02"])
        XCTAssertEqual(PlaylistBrowseParser.extractContinuation(from: page2), "legacy-tok-2")

        let walk = walkPlaylist(first: page1, pagesByToken: ["legacy-tok": page2])
        XCTAssertEqual(walk.ids, ["legacy-01", "legacy-02"])
        XCTAssertEqual(walk.tokensFollowed, ["legacy-tok"])
        XCTAssertEqual(walk.unfollowedToken, "legacy-tok-2")
    }

    func testSingleColumnShelfAndLegacyTokenStillParse() throws {
        let page = try loadFixture("playlist-single-column-page1")
        XCTAssertEqual(videoIDs(in: try XCTUnwrap(PlaylistBrowseParser.extractItems(from: page))), ["tab-01"])
        XCTAssertEqual(PlaylistBrowseParser.extractContinuation(from: page), "tab-tok")
    }

    func testLegacyShelfTokenWinsWhenBothShapesArePresent() {
        let page: [String: Any] = [
            "contents": [
                "twoColumnBrowseResultsRenderer": [
                    "secondaryContents": [
                        "sectionListRenderer": [
                            "contents": [[
                                "musicPlaylistShelfRenderer": [
                                    "contents": [
                                        ["musicResponsiveListItemRenderer": ["videoId": "both-01"]],
                                        continuationRow("item-tok")
                                    ],
                                    "continuations": [[
                                        "nextContinuationData": ["continuation": "legacy-wins"]
                                    ]]
                                ]
                            ]]
                        ]
                    ]
                ]
            ]
        ]
        XCTAssertEqual(PlaylistBrowseParser.extractContinuation(from: page), "legacy-wins")
        XCTAssertEqual(
            videoIDs(in: PlaylistBrowseParser.extractItems(from: page) ?? []),
            ["both-01"]
        )
    }

    func testCommandExecutorContinuationToken() {
        let page: [String: Any] = [
            "onResponseReceivedActions": [[
                "appendContinuationItemsAction": [
                    "continuationItems": [
                        ["musicResponsiveListItemRenderer": ["videoId": "exec-01"]],
                        [
                            "continuationItemRenderer": [
                                "continuationEndpoint": [
                                    "commandExecutorCommand": [
                                        "commands": [[
                                            "continuationCommand": [
                                                "token": "exec-tok",
                                                "request": "CONTINUATION_REQUEST_TYPE_BROWSE"
                                            ]
                                        ]]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]]
        ]
        XCTAssertEqual(videoIDs(in: PlaylistBrowseParser.extractItems(from: page) ?? []), ["exec-01"])
        XCTAssertEqual(PlaylistBrowseParser.extractContinuation(from: page), "exec-tok")
    }

    func testPageCapStopsBeforeTheNextToken() throws {
        let page1 = try loadFixture("playlist-page1-shelf")
        let page2 = try loadFixture("playlist-page2-append")
        let walk = walkPlaylist(
            first: page1,
            pagesByToken: ["tok-2": page2],
            maxPages: 1
        )
        XCTAssertEqual(walk.ids, ["song-01", "song-02"])
        XCTAssertEqual(walk.tokensFollowed, [])
        XCTAssertEqual(walk.unfollowedToken, "tok-2")
        XCTAssertEqual(walk.stop, .pageCap)
    }

    func testRepeatedTokenStops() throws {
        let page1 = try loadFixture("playlist-page1-shelf")
        var page2 = try loadFixture("playlist-page2-append")
        page2["onResponseReceivedActions"] = [[
            "appendContinuationItemsAction": [
                "continuationItems": [
                    ["musicResponsiveListItemRenderer": ["videoId": "song-03"]],
                    continuationRow("tok-2")
                ]
            ]
        ]]
        let walk = walkPlaylist(first: page1, pagesByToken: ["tok-2": page2])
        XCTAssertEqual(walk.ids, ["song-01", "song-02", "song-03"])
        XCTAssertEqual(walk.tokensFollowed, ["tok-2"])
        XCTAssertEqual(walk.stop, .repeatedToken)
    }
}

// MARK: - Walk

private struct PlaylistWalk {
    var ids: [String]
    var tokensFollowed: [String]
    var unfollowedToken: String?
    var stop: ContinuationItems.Stop?
}

private func walkPlaylist(
    first: [String: Any],
    pagesByToken: [String: [String: Any]],
    maxPages: Int = PlaylistBrowseParser.defaultMaxPages
) -> PlaylistWalk {
    var current: [String: Any]? = first
    var requestToken: String?
    var seenTokens = Set<String>()
    var pages = 0
    var ids: [String] = []
    var followed: [String] = []
    var stop: ContinuationItems.Stop?
    while let page = current {
        if let requestToken {
            followed.append(requestToken)
        }
        if let items = PlaylistBrowseParser.extractItems(from: page) {
            ids.append(contentsOf: videoIDs(in: items))
        }
        let token = PlaylistBrowseParser.extractContinuation(from: page)
        pages += 1
        if let reason = ContinuationItems.stopReason(
            token: token,
            seenTokens: &seenTokens,
            pages: pages,
            maxPages: maxPages
        ) {
            stop = reason
            return PlaylistWalk(ids: ids, tokensFollowed: followed, unfollowedToken: token, stop: stop)
        }
        guard let token else {
            return PlaylistWalk(ids: ids, tokensFollowed: followed, unfollowedToken: nil, stop: nil)
        }
        requestToken = token
        current = pagesByToken[token]
    }
    return PlaylistWalk(ids: ids, tokensFollowed: followed, unfollowedToken: requestToken, stop: stop)
}

private func videoIDs(in rows: [[String: Any]]) -> [String] {
    rows.compactMap { row in
        (row["musicResponsiveListItemRenderer"] as? [String: Any])?["videoId"] as? String
    }
}

private func continuationRow(_ token: String) -> [String: Any] {
    [
        "continuationItemRenderer": [
            "continuationEndpoint": [
                "continuationCommand": ["token": token]
            ]
        ]
    ]
}

private func loadFixture(_ name: String) throws -> [String: Any] {
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
