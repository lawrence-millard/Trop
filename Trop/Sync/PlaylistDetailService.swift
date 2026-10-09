//
// PlaylistDetailService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

actor PlaylistDetailService {
    nonisolated static let shared = PlaylistDetailService()
    private let innerTube = InnerTubeClient.tropShared
    private let db = DatabaseService.shared

    func fetchPlaylist(playlistId: String, maxPages: Int = PlaylistBrowseParser.defaultMaxPages) async throws -> Int {
        let browseId = "VL\(playlistId)"
        var allItems: [[String: Any]] = []
        var token: String?
        var seenTokens = Set<String>()
        var pages = 0
        var hadShelf = false
        repeat {
            // Follow-up pages send only the continuation token. WEB_REMIX ignores
            // the token when browseId is also set and returns page 1 again.
            // SwiftyTube puts `continuation` in the JSON body (not a ctoken query)
            // and the music client is WEB_REMIX.
            let json: [String: Any]
            if let token {
                json = try await innerTube.browse(continuation: token)
            } else {
                json = try await innerTube.browse(browseId: browseId)
            }
            if let items = PlaylistBrowseParser.extractItems(from: json) {
                hadShelf = true
                allItems += items
            }
            token = PlaylistBrowseParser.extractContinuation(from: json)
            pages += 1
            if let reason = ContinuationItems.stopReason(
                token: token,
                seenTokens: &seenTokens,
                pages: pages,
                maxPages: maxPages
            ) {
                switch reason {
                case .repeatedToken:
                    Log.sync.error("fetchPlaylist \(playlistId): repeated continuation token, stopping")
                case .pageCap:
                    Log.sync.error("fetchPlaylist \(playlistId): hit \(maxPages)-page cap, stopping")
                }
                break
            }
        } while token != nil

        guard hadShelf else {
            throw InnerTubeError.invalidResponse
        }

        let snapshot = allItems
        try await db.write { db in
            let existing = try PlaylistEntity.fetchOne(db, key: playlistId)
            let entity = PlaylistEntity.merging(
                existing: existing,
                id: playlistId,
                browseId: browseId,
                name: "Playlist",
                remoteSongCount: snapshot.count
            )
            try entity.save(db)

            // Clear existing song mappings and re-insert
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id = ?", arguments: [playlistId])
            var skipped = 0
            for (index, rawItem) in snapshot.enumerated() {
                guard let renderer = rawItem["musicResponsiveListItemRenderer"] as? [String: Any],
                      let videoId = Self.playlistRowVideoId(renderer) else {
                    skipped += 1
                    if skipped <= 3 {
                        Log.sync.debug("fetchPlaylist \(playlistId): skipping row \(index), keys=\(rawItem.keys.sorted())")
                    }
                    continue
                }
                let nav = renderer["navigationEndpoint"] as? [String: Any]
                let watch = nav?["watchEndpoint"] as? [String: Any]
                let setVideoId = watch?["playlistSetVideoId"] as? String

                if let songItem = SongItem.from(renderer) {
                    let existing = try SongEntity.fetchOne(db, key: videoId)
                    let entity = SongEntity.merging(
                        existing: existing,
                        id: videoId,
                        title: songItem.title,
                        artistName: songItem.artists.first?.name,
                        albumName: songItem.album,
                        duration: songItem.duration,
                        thumbnailUrl: songItem.thumbnailUrl
                    )
                    try entity.save(db)
                }

                let map = PlaylistSongMap(
                    id: nil,
                    playlistId: playlistId,
                    songId: videoId,
                    position: index,
                    setVideoId: setVideoId
                )
                try map.insert(db, onConflict: .ignore)
            }
            if skipped > 0 {
                Log.sync.debug("fetchPlaylist \(playlistId): skipped \(skipped)/\(snapshot.count) rows without video id")
            }
        }
        return allItems.count
    }

    private static func playlistRowVideoId(_ renderer: [String: Any]) -> String? {
        if let videoId = renderer["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let itemData = renderer["playlistItemData"] as? [String: Any],
           let videoId = itemData["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let nav = renderer["navigationEndpoint"] as? [String: Any],
           let watch = nav["watchEndpoint"] as? [String: Any],
           let videoId = watch["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let overlay = renderer["overlay"] as? [String: Any],
           let overlayRenderer = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
           let content = overlayRenderer["content"] as? [String: Any],
           let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
           let nav = playButton["playNavigationEndpoint"] as? [String: Any],
           let watch = nav["watchEndpoint"] as? [String: Any],
           let videoId = watch["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        return nil
    }
}
