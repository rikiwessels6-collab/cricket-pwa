import SwiftUI
import SwiftData
import PhotosUI
import SteadyCore

/// Photo of a plate -> estimate -> the person checks and corrects it -> logged with a timestamp.
/// Nothing is logged until they tap Add.
struct PlateFlow: View {
    let meal: MealSlot
    let day: Date
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]

    enum Stage { case capture, analysing, confirm(PlateResult), failed(String) }
    @State private var stage: Stage = .capture
    @State private var image: UIImage?
    @State private var note = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    private var consented: Bool { settings.first?.consents[DataType.plateAnalysis.rawValue] != nil }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .capture: capture
                case .analysing:
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Estimating your plate…").foregroundStyle(Color.inkMuted)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                case .confirm(let result):
                    ConfirmPlate(result: result, meal: meal, day: day, note: note) { dismiss(); onDone() }
                case .failed(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Color.gold)
                        Text(message).multilineTextAlignment(.center)
                        Button("Try again") { stage = .capture }.buttonStyle(.borderedProminent)
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.night.ignoresSafeArea())
            .navigationTitle("Plate photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker(image: $image).ignoresSafeArea() }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { image = img }
                }
            }
        }
    }

    private var capture: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { consented },
                    set: { on in settings.first?.consents[DataType.plateAnalysis.rawValue] = on ? .now : nil })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send plate photos for estimates")
                        Text("The photo is sent once to estimate the food and macros, then discarded. No name, health or account details go with it. Off by default; change it any time in Settings.")
                            .font(.footnote).foregroundStyle(Color.inkMuted)
                    }
                }
                .accessibilityIdentifier("plateConsent")
            }
            if consented {
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .frame(maxWidth: .infinity)
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label(image == nil ? "Take a photo" : "Retake", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose from photos", systemImage: "photo") }
                    Text("Tip: shoot from above, with the whole plate in view and good light. Include a fork for scale if you can.")
                        .font(.footnote).foregroundStyle(Color.inkMuted)
                }
                Section("Anything the photo can't show?") {
                    TextField("e.g. cooked in 1 tbsp olive oil", text: $note, axis: .vertical).lineLimit(1...3)
                }
                Section {
                    Button { analyse() } label: { Text("Analyse").frame(maxWidth: .infinity).fontWeight(.semibold) }
                        .disabled(image == nil || !PlateRelay.isConfigured)
                        .accessibilityIdentifier("analysePlate")
                    if !PlateRelay.isConfigured {
                        Text("Plate photos aren't set up in this build yet.").font(.footnote).foregroundStyle(Color.inkMuted)
                    }
                } footer: {
                    Text("Estimates are a starting point. You'll check and correct every item before anything is logged.")
                }
            }
        }
        .themedList()
    }

    private func analyse() {
        guard let image, let data = PlateRelay.prepare(image) else { stage = .failed("Couldn't prepare that photo."); return }
        stage = .analysing
        let request = PlateRequest(imageBase64: data.base64EncodedString(), note: note)
        Task {
            do {
                let result = try await PlateRelay.estimate(request)
                if result.notFood || result.items.isEmpty {
                    stage = .failed("That doesn't look like a plate of food. Try another photo.")
                } else {
                    stage = .confirm(result)
                }
            } catch {
                stage = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Confirm

struct ConfirmPlate: View {
    let result: PlateResult
    let meal: MealSlot
    let day: Date
    let note: String
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @State private var items: [PlateItem]
    @State private var answers: [String: Int] = [:]
    @State private var slot: MealSlot
    @State private var eatenAt: Date

    init(result: PlateResult, meal: MealSlot, day: Date, note: String, onDone: @escaping () -> Void) {
        self.result = result; self.meal = meal; self.day = day; self.note = note; self.onDone = onDone
        _items = State(initialValue: result.items)
        _slot = State(initialValue: meal)
        var when = Date.now
        if !Calendar.current.isDateInToday(day) {
            let t = Calendar.current.dateComponents([.hour, .minute], from: .now)
            when = Calendar.current.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: day) ?? day
        }
        _eatenAt = State(initialValue: when)
    }

    private var total: Macros { PlateMath.total(items: items, questions: result.questions, answers: answers) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    stat("\(Int(total.kcal.rounded()))", "kcal")
                    stat("\(Int(total.protein.rounded()))", "protein")
                    stat("\(Int(total.carbs.rounded()))", "carbs")
                    stat("\(Int(total.fat.rounded()))", "fat")
                }
                if let overall = PlateMath.overall(items) {
                    Label(overall.label, systemImage: overall == .high ? "checkmark.seal" : "scalemass")
                        .font(.footnote).foregroundStyle(overall == .high ? Color.emerald : Color.gold)
                }
            } footer: { Text("An estimate from a photo. Fix any amount that looks wrong; the numbers update.") }

            Section("What we found") {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(items[i].name).font(.headline).foregroundStyle(Color.ink)
                            Spacer()
                            Text(items[i].confidence.label).font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background((items[i].confidence == .high ? Color.emerald : Color.gold).opacity(0.18), in: Capsule())
                        }
                        HStack {
                            TextField("Grams", value: Binding(
                                get: { items[i].grams },
                                set: { items[i] = items[i].scaled(toGrams: max(0, $0)) }), format: .number)
                                .keyboardType(.decimalPad).font(.title3.weight(.semibold).monospacedDigit())
                            Text("g").foregroundStyle(Color.inkMuted)
                            Spacer()
                            Text("\(Int(items[i].kcal.rounded())) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(Color.inkMuted)
                        }
                        if !items[i].basis.isEmpty { Text(items[i].basis).font(.caption).foregroundStyle(Color.inkMuted) }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { items.remove(atOffsets: $0) }
            }

            ForEach(result.questions, id: \.id) { q in
                Section(q.text) {
                    Picker(q.text, selection: Binding(get: { answers[q.id] ?? 0 }, set: { answers[q.id] = $0 })) {
                        ForEach(q.options.indices, id: \.self) { j in
                            Text(q.options[j].kcal > 0 ? "\(q.options[j].label) (+\(Int(q.options[j].kcal.rounded())) kcal)" : q.options[j].label).tag(j)
                        }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }

            Section("When") {
                Picker("Meal", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.label).tag($0) } }
                DatePicker("Eaten at", selection: $eatenAt)
            }

            Section {
                Button { save() } label: { Text("Add to \(slot.label)").frame(maxWidth: .infinity).fontWeight(.semibold) }
                    .disabled(items.isEmpty)
                    .accessibilityIdentifier("addPlate")
            }
        }
        .themedList()
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.ink)
            Text(l).font(.caption2).foregroundStyle(Color.inkMuted)
        }.frame(maxWidth: .infinity)
    }

    private func save() {
        for (n, item) in items.enumerated() {
            guard let per100 = item.per100 else { continue }
            let food = FoodItem(id: "photo-\(UUID().uuidString)", name: item.name, brand: nil, barcode: nil,
                                per100: per100, servingGrams: nil, servingLabel: nil)
            let entry = FoodEntry(item: food, grams: item.grams, meal: slot, source: .photo, eatenAt: eatenAt)
            entry.confidence = item.confidence.rawValue
            _ = n
            context.insert(entry)
        }
        // Hidden calories the person told us about are logged as their own line, so they can be seen and edited.
        for q in result.questions {
            let i = answers[q.id] ?? 0
            guard q.options.indices.contains(i), q.options[i].kcal > 0 else { continue }
            let opt = q.options[i]
            let placeholder = FoodItem(id: "photo-\(UUID().uuidString)", name: "\(opt.label) (\(q.text.trimmingCharacters(in: CharacterSet(charactersIn: "?"))))",
                                       brand: nil, barcode: nil, per100: Per100(kcal: 0, protein: 0, carbs: 0, fat: 0),
                                       servingGrams: nil, servingLabel: nil)
            let entry = FoodEntry(item: placeholder, grams: 0, meal: slot, source: .photo, eatenAt: eatenAt)
            entry.kcal = opt.kcal; entry.protein = opt.protein; entry.carbs = opt.carbs; entry.fat = opt.fat
            entry.confidence = PlateConfidence.medium.rawValue
            context.insert(entry)
        }
        try? context.save()
        onDone()
    }
}

// MARK: - Camera

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
