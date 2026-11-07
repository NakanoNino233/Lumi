import ActivityKit
import Foundation

struct LumiActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stage: String
        var affection: Int
        var latest: String
        var anniversaryTitle: String
        var anniversaryDate: Date?
    }
    var friend: String
    var characterID: UUID
}
