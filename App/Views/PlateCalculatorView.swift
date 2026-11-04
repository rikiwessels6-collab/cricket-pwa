import SwiftUI
import SwiftData
import SteadyCore

/// What goes on each side of the bar, using the plates you own. Also where you set your bar, plates and warm-up style.
struct PlateCalculatorView: View {
    @Query private var settings: [AppSettings]
    @State private var target: Double

    static let plateWeights: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    init(target: Double = 60) { _target = State(initialValue: target) }

    private func stock(_ s: AppSettings) -> [PlateStock] {
        Self.plateWeights.map { PlateStock(weight: $0, pairs: s.plateStock[NumberText.format($0)] ?? 0) }
    }

    var body: some View {
        Form {
            if let s = settings.first {
                let load = BarLoading.load(target: target, bar: s.barWeightKg, stock: stock(s))
                Section("Target weight") {
                    HStack {
                        TextField("kg", value: $target, format: .number).keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .accessibilityIdentifier("plateTarget")
                        Text("kg").foregroundStyle(.secondary)
                    }
                }
                Section {
                    if load.perSide.isEmpty {
                        Text(target <= s.barWeightKg ? "Just the bar (\(NumberText.format(s.barWeightKg)) kg)." : "No plates fit with what you have set.")
                            .foregroundStyle(Color.inkMuted)
                    }
                    ForEach(load.perSide) { p in
                        HStack {
                            Text("\(p.count) × \(NumberText.format(p.weight)) kg").font(.title3.weight(.semibold).monospacedDigit())
                            Spacer()
                        }
                    }
                } header: { Text("Each side") } footer: {
                    if load.isExact {
                        Text("Total \(NumberText.format(load.loaded)) kg including the \(NumberText.format(s.barWeightKg)) kg bar.")
                    } else {
                        Text("Closest you can load is \(NumberText.format(load.loaded)) kg, about \(NumberText.format((load.shortfall * 100).rounded() / 100)) kg short of your target.")
                    }
                }
                Section {
                    Stepper(value: Binding(get: { s.barWeightKg }, set: { s.barWeightKg = $0 }), in: 5...30, step: 2.5) {
                        LabeledContent("Bar weight", value: "\(NumberText.format(s.barWeightKg)) kg")
                    }
                    ForEach(Self.plateWeights, id: \.self) { w in
                        let key = NumberText.format(w)
                        Stepper(value: Binding(get: { s.plateStock[key] ?? 0 }, set: { s.plateStock[key] = $0 }), in: 0...12) {
                            LabeledContent("\(key) kg plates", value: "\(s.plateStock[key] ?? 0) pair\((s.plateStock[key] ?? 0) == 1 ? "" : "s")")
                        }
                    }
                    Picker("Warm-up sets", selection: Binding(get: { s.warmupStyleRaw }, set: { s.warmupStyleRaw = $0 })) {
                        ForEach(Warmup.Style.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: { Text("My bar, plates and warm-ups") } footer: {
                    Text("Pairs means one plate for each side. Warm-up sets appear on main lifts as a guide you can skip.")
                }
            }
        }
        .themedList()
        .navigationTitle("Plate calculator")
        .navigationBarTitleDisplayMode(.inline)
    }
}
