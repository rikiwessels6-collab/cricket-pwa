import SwiftUI
import SteadyCore

/// A tickable warm-up or cool-down. Ticks are just for today and aren't saved.
struct RoutineCard: View {
    let kind: Routine.Kind
    let version: SessionVersion
    @State private var open = false
    @State private var done: Set<String> = []

    var body: some View {
        let steps = Routine.steps(kind, version: version)
        let title = kind == .warmup ? "Warm-up" : "Cool-down"
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    Button {
                        if done.contains(step.id) { done.remove(step.id) } else { done.insert(step.id) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: done.contains(step.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done.contains(step.id) ? Color.emerald : Color.inkMuted)
                            Text(step.text).foregroundStyle(Color.ink).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(done.contains(step.id) ? .isSelected : [])
                }
                Text("A guide only. Skip anything that doesn't suit you today.").font(.caption2).foregroundStyle(Color.inkMuted)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(title).font(.headline).foregroundStyle(Color.ink)
                Spacer()
                Text("\(Routine.minutes(kind, version: version)) min").font(.caption).foregroundStyle(Color.inkMuted)
            }
        }
        .tint(Color.gold)
        .card()
    }
}
