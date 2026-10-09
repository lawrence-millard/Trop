//
//  PlaylistBrowseParser.swift
//  Trop
//
//  Playlist shelf rows and continuation tokens for page 1 and later pages.
//

import Foundation

enum PlaylistBrowseParser {
    /// Page cap already used by `PlaylistDetailService.fetchPlaylist`.
    static let defaultMaxPages = 100

    static func extractItems(from json: [String: Any]) -> [[String: Any]]? {
        if let firstSection = BrowseLens.firstBrowseSection(json),
           let shelf = playlistShelf(firstSection),
           let items = shelf["contents"] as? [[String: Any]] {
            return ContinuationItems.songRows(items)
        }
        let contentLists = twoColumnShelves(from: json).compactMap { $0["contents"] as? [[String: Any]] }
        if !contentLists.isEmpty {
            return ContinuationItems.songRows(contentLists.flatMap { $0 })
        }
        if let shelf = continuationShelf(json),
           let items = shelf["contents"] as? [[String: Any]] {
            return ContinuationItems.songRows(items)
        }
        if let appended = ContinuationItems.appendedItems(from: json) {
            return appended
        }
        Log.sync.debug("extractPlaylistItems: no shelf found, top keys=\(json.keys.sorted())")
        if let contents = json["contents"] as? [String: Any] {
            Log.sync.debug("extractPlaylistItems: contents keys=\(contents.keys.sorted())")
        }
        return nil
    }

    static func extractContinuation(from json: [String: Any]) -> String? {
        if let firstSection = BrowseLens.firstBrowseSection(json),
           let shelf = playlistShelf(firstSection),
           let token = ContinuationItems.token(in: shelf) {
            return token
        }
        for shelf in twoColumnShelves(from: json) {
            if let token = ContinuationItems.token(in: shelf) {
                return token
            }
        }
        if let twoCol = (json["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any],
           let secondary = twoCol["secondaryContents"] as? [String: Any],
           let sectionList = secondary["sectionListRenderer"] as? [String: Any],
           let token = ContinuationItems.token(in: sectionList) {
            return token
        }
        if let shelf = continuationShelf(json),
           let token = ContinuationItems.token(in: shelf) {
            return token
        }
        return ContinuationItems.appendedToken(from: json)
    }

    private static func playlistShelf(_ section: [String: Any]) -> [String: Any]? {
        section["musicPlaylistShelfRenderer"] as? [String: Any]
            ?? section["musicShelfRenderer"] as? [String: Any]
    }

    private static func continuationShelf(_ json: [String: Any]) -> [String: Any]? {
        guard let continuationContents = json["continuationContents"] as? [String: Any] else { return nil }
        return continuationContents["musicPlaylistShelfContinuation"] as? [String: Any]
            ?? continuationContents["musicShelfContinuation"] as? [String: Any]
    }

    /// Every song shelf from a twoColumnBrowseResultsRenderer response
    /// (secondaryContents → sectionListRenderer), unwrapping
    /// itemSectionRenderer wrappers like the detail parser does.
    private static func twoColumnShelves(from json: [String: Any]) -> [[String: Any]] {
        guard let twoCol = (json["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any],
              let secondary = twoCol["secondaryContents"] as? [String: Any],
              let sectionList = secondary["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]] else { return [] }
        var shelves: [[String: Any]] = []
        for section in sections {
            let unwrapped = (section["itemSectionRenderer"] as? [String: Any])
                .flatMap { ($0["contents"] as? [[String: Any]])?.first }
                ?? section
            if let shelf = playlistShelf(unwrapped) {
                shelves.append(shelf)
            }
        }
        return shelves
    }
}
