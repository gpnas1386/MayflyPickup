import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct MayflyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var topCode: String
        public var stationName: String
        public var total: Int
        public var speech: String

        public init(topCode: String, stationName: String, total: Int, speech: String) {
            self.topCode = topCode
            self.stationName = stationName
            self.total = total
            self.speech = speech
        }
    }

    public var total: Int
    public var stationHint: String

    public init(total: Int, stationHint: String) {
        self.total = total
        self.stationHint = stationHint
    }
}
#endif
