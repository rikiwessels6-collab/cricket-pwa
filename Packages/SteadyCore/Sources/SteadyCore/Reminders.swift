import Foundation

/// A repeating weekly reminder. The app turns these into local notifications (nothing leaves the phone).
public struct ReminderSlot: Equatable, Sendable, Identifiable {
    public var id: String
    public var weekday: Int      // 1 = Sunday ... 7 = Saturday
    public var hour: Int
    public var minute: Int
    public var title: String
    public var body: String
}

public enum Reminders {
    public static let idPrefix = "steady."

    /// One reminder per training weekday and one for the weekly check-in. Plain, neutral wording.
    public static func slots(trainingWeekdays: [Int], checkInWeekday: Int?, hour: Int, minute: Int) -> [ReminderSlot] {
        let h = min(max(hour, 0), 23), m = min(max(minute, 0), 59)
        var out: [ReminderSlot] = Set(trainingWeekdays).filter { (1...7).contains($0) }.sorted().map {
            ReminderSlot(id: "\(idPrefix)session.\($0)", weekday: $0, hour: h, minute: m,
                         title: "Training day", body: "Your session is ready when you are.")
        }
        if let c = checkInWeekday, (1...7).contains(c) {
            out.append(ReminderSlot(id: "\(idPrefix)checkin", weekday: c, hour: h, minute: m,
                                    title: "Weekly check-in", body: "It only takes a minute."))
        }
        return out
    }
}
