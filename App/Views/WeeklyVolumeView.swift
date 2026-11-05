import SwiftUI
import SwiftData
import SteadyCore

/// Hard sets per muscle for a week, from the sets you actually logged.
struct WeeklyVolumeView: View {
    @Environment(ContentStore.self) private var store
    @Query private var logs: [WorkoutLog]
    @State private var weeksBack = 0

    private var range: (start: Date, end: Date) { VolumeReport.weekRange(containing: .now, weeksBack: weeksBack) }

    private var setCounts: [String: Int] {
        var out: [String: Int] = [:]
        for log in logs where log.startedAt >= range.start && log.startedAt < range.end {
            for s in log.sets { out[s.exerciseId, default: 0] += 1 }
        }
        return out
    }

    var body: some View {
        let content = store.content
        let counts = setCounts
        let rows = content.map { VolumeReport.week(setCounts: counts, library: $0.library, muscles: $0.muscleIds) } ?? []
        let trained = rows.filter { $0.direct > 0 || $0.indirect > 0 }
        let untrained = rows.filter { $0.direct == 0 && $0.indirect == 0 }
        List {
            Section {
                Picker("Week", selection: $weeksBack) {
                    Text("This week").tag(0)
                    Text("Last week").tag(1)
                    Text("2 weeks ago").tag(2)
                    Text("3 weeks ago").tag(3)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("volumeWeek")
                Text("\(range.start.formatted(.dateTime.day().month(.abbreviated))) to \(range.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated))) · \(counts.values.reduce(0, +)) sets logged")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if trained.isEmpty {
                Section { Text("No sets logged this week yet.").foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(trained) { row in MuscleRow(row: row) }
                } header: { Text("Sets per muscle") } footer: {
                    Text("Direct sets are the main muscle an exercise works. Indirect is half credit for the helpers, such as triceps on a bench press. Warm-ups are not counted. About 10 to 20 direct sets a week suits many people for building muscle; it is a guide, not a rule, and you know your recovery best.")
                }
            }
            if !untrained.isEmpty && !trained.isEmpty {
                Section("Not trained this week") {
                    Text(untrained.map { VolumeReport.prettyName($0.muscle) }.joined(separator: ", "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .themedList()
        .navigationTitle("Weekly volume")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MuscleRow: View {
    let row: MuscleWeek

    private var colour: Color {
        switch row.band {
        case .inRange: return Color.emerald
        case .low, .none: return Color.gold
        case .high: return Color.orange
        }
    }
    private var note: String {
        switch row.band {
        case .inRange: return "In the usual range"
        case .low: return "Under 10"
        case .high: return "Over 20"
        case .none: return "Indirect only"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(VolumeReport.prettyName(row.muscle))
                Spacer()
                Text(NumberText.format(row.direct)).font(.headline.monospacedDigit())
                Text("direct").font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let full = VolumeReport.upperTarget * 1.25
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    // the 10 to 20 band
                    Capsule().fill(Color.emerald.opacity(0.22))
                        .frame(width: geo.size.width * CGFloat((VolumeReport.upperTarget - VolumeReport.lowerTarget) / full))
                        .offset(x: geo.size.width * CGFloat(VolumeReport.lowerTarget / full))
                    Capsule().fill(colour)
                        .frame(width: max(6, geo.size.width * CGFloat(min(row.direct, full) / full)))
                        .opacity(row.direct > 0 ? 1 : 0)
                }
            }
            .frame(height: 8)
            HStack {
                Text(note).font(.caption).foregroundStyle(colour)
                Spacer()
                if row.indirect > 0 {
                    Text("+\(NumberText.format(row.indirect)) indirect").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
