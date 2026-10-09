//
//  ContinuationItems.swift
//  Trop
//
//  Shared walks for InnerTube browse pagination.
//
//  WEB_REMIX (SwiftyTube's music client) returns two continuation shapes:
//  - Legacy: `continuations[0].nextContinuationData.continuation`, with the
//    next page under `continuationContents`.
//  - Current: a trailing `continuationItemRenderer` whose
//    `continuationEndpoint.continuationCommand.token` is sent back as the
//    browse body's `continuation` field (not a `ctoken` query). The next page
//    is `onResponseReceivedActions[].appendContinuationItemsAction.continuationItems`.
//

import Foundation

enum ContinuationItems {
    enum Stop: Equatable {
        case repeatedToken
        case pageCap
    }

    /// Same stop rules as the pre-existing playlist fetch loop: a repeated
    /// token, then the page cap. A nil token is not a stop by itself; callers
    /// end the loop on nil.
    static func stopReason(
        token: String?,
        seenTokens: inout Set<String>,
        pages: Int,
        maxPages: Int
    ) -> Stop? {
        if let token, !seenTokens.insert(token).inserted {
            return .repeatedToken
        }
        if pages >= maxPages {
            return .pageCap
        }
        return nil
    }

    /// Drops continuation sentinels so they are not stored as tracks.
    static func songRows(_ rows: [[String: Any]]) -> [[String: Any]] {
        rows.filter { $0["continuationItemRenderer"] == nil }
    }

    /// Rows from a modern continuation response. Nil when that action is absent
    /// so callers can still read a legacy `continuationContents` payload.
    static func appendedItems(from json: [String: Any]) -> [[String: Any]]? {
        guard let actions = json["onResponseReceivedActions"] as? [[String: Any]] else { return nil }
        var rows: [[String: Any]] = []
        var found = false
        for action in actions {
            guard let append = action["appendContinuationItemsAction"] as? [String: Any],
                  let items = append["continuationItems"] as? [[String: Any]] else { continue }
            found = true
            rows.append(contentsOf: songRows(items))
        }
        guard found else { return nil }
        return rows
    }

    /// Next token carried by an `appendContinuationItemsAction` response.
    static func appendedToken(from json: [String: Any]) -> String? {
        guard let actions = json["onResponseReceivedActions"] as? [[String: Any]] else { return nil }
        for action in actions {
            guard let append = action["appendContinuationItemsAction"] as? [String: Any] else { continue }
            if let token = token(in: append) {
                return token
            }
        }
        return nil
    }

    /// Next browse token on a shelf, grid, or continuation action.
    /// Legacy `nextContinuationData` wins when it is present so older payloads
    /// keep the token they already exposed. Otherwise the token is read from a
    /// `continuationItemRenderer` row.
    static func token(in container: [String: Any], depth: Int = 0) -> String? {
        if let token = legacyContinuationToken(in: container) {
            return token
        }
        if let token = token(inRows: container["contents"] as? [[String: Any]]) {
            return token
        }
        if let token = token(inRows: container["items"] as? [[String: Any]]) {
            return token
        }
        if let token = token(inRows: container["continuationItems"] as? [[String: Any]]) {
            return token
        }
        if depth < 2 {
            for key in nestedRendererKeys {
                guard let nested = container[key] as? [String: Any],
                      let token = token(in: nested, depth: depth + 1) else { continue }
                return token
            }
        }
        return nil
    }

    private static let nestedRendererKeys = [
        "musicPlaylistShelfRenderer",
        "musicShelfRenderer",
        "gridRenderer",
        "musicPlaylistShelfContinuation",
        "musicShelfContinuation",
        "gridContinuation"
    ]

    /// `continuations[0].nextContinuationData.continuation`, matching
    /// `InnerTubeDecode.continuationToken`.
    private static func legacyContinuationToken(in dict: [String: Any]) -> String? {
        guard let continuations = dict["continuations"] as? [[String: Any]],
              let first = continuations.first,
              let next = first["nextContinuationData"] as? [String: Any],
              let token = next["continuation"] as? String,
              !token.isEmpty else { return nil }
        return token
    }

    private static func token(inRows rows: [[String: Any]]?) -> String? {
        guard let rows else { return nil }
        for row in rows.reversed() {
            if let token = token(inContinuationItem: row) {
                return token
            }
        }
        return nil
    }

    private static func token(inContinuationItem row: [String: Any]) -> String? {
        guard let renderer = row["continuationItemRenderer"] as? [String: Any],
              let endpoint = renderer["continuationEndpoint"] as? [String: Any] else { return nil }
        if let command = endpoint["continuationCommand"] as? [String: Any],
           let token = nonEmptyToken(command) {
            return token
        }
        guard let executor = endpoint["commandExecutorCommand"] as? [String: Any],
              let commands = executor["commands"] as? [[String: Any]] else { return nil }
        for command in commands {
            guard let continuation = command["continuationCommand"] as? [String: Any],
                  let token = nonEmptyToken(continuation) else { continue }
            let request = continuation["request"] as? String
            if request == nil || request == "CONTINUATION_REQUEST_TYPE_BROWSE" {
                return token
            }
        }
        return nil
    }

    private static func nonEmptyToken(_ command: [String: Any]) -> String? {
        guard let token = command["token"] as? String, !token.isEmpty else { return nil }
        return token
    }
}
