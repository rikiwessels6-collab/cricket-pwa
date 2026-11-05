import SwiftUI
import SwiftData
import VisionKit
import PhotosUI
import SteadyCore

// MARK: - Open Food Facts

enum FoodService {
    static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue(OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { throw URLError(.badServerResponse) }
        return data
    }

    static func lookup(barcode: String) async throws -> FoodItem? {
        guard let url = OpenFoodFacts.productURL(barcode: barcode) else { return nil }
        return try OpenFoodFacts.parseProduct(try await get(url))
    }

    static func search(_ query: String) async throws -> [FoodItem] {
        guard let url = OpenFoodFacts.searchURL(query) else { return [] }
        return try OpenFoodFacts.parseSearch(try await get(url))
    }
}

extension Calendar {
    func dayRange(_ date: Date) -> (Date, Date) {
        let start = startOfDay(for: date)
        return (start, self.date(byAdding: .day, value: 1, to: start) ?? start)
    }
}

func totals(_ entries: [FoodEntry]) -> Macros { entries.reduce(Macros()) { $0 + $1.macros } }

// MARK: - Food tab

struct FoodView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [NutritionPlan]
    @Query(sort: \FoodEntry.eatenAt) private var entries: [FoodEntry]
    @State private var day = Date.now
    @State private var addingTo: MealSlot?
    @State private var editing: FoodEntry?

    private var dayEntries: [FoodEntry] {
        let (s, e) = Calendar.current.dayRange(day)
        return entries.filter { $0.eatenAt >= s && $0.eatenAt < e }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dayHeader
                    if let plan = plans.first { FoodCard(plan: plan, totals: totals(dayEntries)) }
                    ForEach(MealSlot.allCases) { meal in mealCard(meal) }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $addingTo) { meal in AddFoodSheet(meal: meal, day: day) }
            .sheet(item: $editing) { entry in EditEntrySheet(entry: entry) }
        }
    }

    private var dayHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Calendar.current.isDateInToday(day) ? "TODAY" : day.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                Text(day.formatted(.dateTime.day().month(.wide))).font(.largeTitle.weight(.bold)).foregroundStyle(Color.ink)
            }
            Spacer()
            HStack(spacing: 8) {
                dayButton("chevron.left", -1)
                dayButton("chevron.right", 1).disabled(Calendar.current.isDateInToday(day))
            }
        }
        .padding(.top, 8)
    }

    private func dayButton(_ icon: String, _ step: Int) -> some View {
        Button {
            day = Calendar.current.date(byAdding: .day, value: step, to: day) ?? day
        } label: {
            Image(systemName: icon).font(.headline).frame(width: 40, height: 40)
                .background(Color.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.ink)
        .accessibilityLabel(step < 0 ? "Previous day" : "Next day")
    }

    private func mealCard(_ meal: MealSlot) -> some View {
        let items = dayEntries.filter { $0.meal == meal }
        let kcal = items.reduce(0) { $0 + $1.kcal }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(meal.label.uppercased()).font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                Spacer()
                if kcal > 0 { Text("\(Int(kcal.rounded())) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(Color.inkMuted) }
                Button { addingTo = meal } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.bold)).foregroundStyle(Color.night)
                        .frame(width: 30, height: 30).background(LinearGradient.brand, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(meal.label)")
                .accessibilityIdentifier("add-\(meal.rawValue)")
            }
            if items.isEmpty {
                Text("Nothing logged").font(.subheadline).foregroundStyle(Color.inkMuted.opacity(0.7))
            }
            ForEach(items) { e in
                Button { editing = e } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.body.weight(.medium)).foregroundStyle(Color.ink).lineLimit(1)
                            Text("\(e.eatenAt.formatted(date: .omitted, time: .shortened)) · \(Int(e.grams.rounded())) g · P \(Int(e.protein.rounded())) C \(Int(e.carbs.rounded())) F \(Int(e.fat.rounded()))")
                                .font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
                        }
                        Spacer()
                        Text("\(Int(e.kcal.rounded()))").font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Color.ink)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

// MARK: - Adding food

struct AddFoodSheet: View {
    let meal: MealSlot
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedFood.lastUsed, order: .reverse) private var saved: [SavedFood]
    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var searching = false
    @State private var message: String?
    @State private var scanning = false
    @State private var picked: (item: FoodItem, source: FoodSource)?
    @State private var creating = false
    @State private var newBarcode: String?
    @State private var plate = false
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        actionButton("Scan barcode", "barcode.viewfinder") { scanning = true }
                            .accessibilityIdentifier("scanBarcode")
                        actionButton("Plate photo", "camera.viewfinder") { plate = true }
                            .accessibilityIdentifier("platePhoto")
                        actionButton("Create food", "square.and.pencil") { newBarcode = nil; creating = true }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(Color.inkMuted) } }
                if !results.isEmpty {
                    Section("Results") { ForEach(results) { row($0, source: .search) } }
                } else {
                    Section {
                        Picker("Show", selection: $tab) {
                            Text("Recent").tag(0); Text("Favourites").tag(1); Text("My foods").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        ForEach(list) { s in if let item = s.item { row(item, source: s.isCustom ? .saved : .recent) } }
                        if list.isEmpty {
                            Text(tab == 0 ? "Foods you log appear here." : tab == 1 ? "Tap the star on a food to keep it here." : "Foods you create appear here.")
                                .font(.footnote).foregroundStyle(Color.inkMuted)
                        }
                    }
                }
                Section {
                    Text("Product data from Open Food Facts (openfoodfacts.org), licensed under the ODbL.")
                        .font(.caption2).foregroundStyle(Color.inkMuted)
                }
            }
            .themedList()
            .overlay { if searching { ProgressView().controlSize(.large) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .onChange(of: query) { _, q in if q.isEmpty { results = []; message = nil } }
            .navigationTitle("Add to \(meal.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(isPresented: $scanning) {
                BarcodeScanner { code in
                    scanning = false
                    Task { await lookup(code) }
                } onCancel: { scanning = false }
            }
            .sheet(isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } })) {
                if let p = picked {
                    PortionSheet(item: p.item, source: p.source, meal: meal, day: day) { dismiss() }
                }
            }
            .sheet(isPresented: $plate) { PlateFlow(meal: meal, day: day) { dismiss() } }
            .sheet(isPresented: $creating) {
                CustomFoodForm(barcode: newBarcode) { item in
                    creating = false
                    if !saved.contains(where: { $0.foodId == item.id }) {
                        context.insert(SavedFood(item: item, isCustom: true))
                        try? context.save()
                    }
                    let source: FoodSource = item.barcode == nil ? .manual : .barcode
                    picked = (item, source)
                }
            }
        }
    }

    private var list: [SavedFood] {
        switch tab {
        case 1: return saved.filter(\.isFavourite)
        case 2: return saved.filter(\.isCustom)
        default: return Array(saved.filter { $0.useCount > 0 }.prefix(25))
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.hairline))
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: FoodItem, source: FoodSource) -> some View {
        Button { picked = (item, source) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(Color.ink).lineLimit(2)
                    Text([item.brand, item.servingLabel.map { "serve \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Text("\(Int(item.per100.kcal.rounded())) kcal/100g").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let local = saved.compactMap(\.item).filter { $0.name.localizedCaseInsensitiveContains(q) }
        searching = true; message = nil
        defer { searching = false }
        do {
            let remote = try await FoodService.search(q)
            results = local + remote.filter { r in !local.contains { $0.id == r.id } }
            if results.isEmpty { message = "No matches. Try fewer words, or create the food." }
        } catch {
            results = local
            message = "Couldn't reach the food database. Showing your saved foods."
        }
    }

    private func lookup(_ code: String) async {
        if let hit = saved.first(where: { $0.foodId == code })?.item { picked = (hit, .barcode); return }
        searching = true; defer { searching = false }
        do {
            if let item = try await FoodService.lookup(barcode: code) { picked = (item, .barcode) }
            else {
                message = "Barcode \(code) isn't in the food database. Add it from the pack once and it's saved on your phone for next time."
                newBarcode = code
                creating = true
            }
        } catch {
            message = "Couldn't look up that barcode. Check your connection and try again."
        }
    }
}

struct PortionSheet: View {
    let item: FoodItem
    let source: FoodSource
    let meal: MealSlot
    let day: Date
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var saved: [SavedFood]
    @State private var grams: Double = 100
    @State private var slot: MealSlot = .snacks
    @State private var eatenAt = Date.now
    @State private var favourite = false

    var body: some View {
        let m = item.macros(grams: grams)
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
                        if let b = item.brand { Text(b).font(.subheadline).foregroundStyle(Color.inkMuted) }
                    }
                    HStack(spacing: 0) {
                        stat("\(Int(m.kcal.rounded()))", "kcal")
                        stat("\(Int(m.protein.rounded()))", "protein")
                        stat("\(Int(m.carbs.rounded()))", "carbs")
                        stat("\(Int(m.fat.rounded()))", "fat")
                    }
                }
                Section("Amount") {
                    HStack {
                        TextField("Grams", value: $grams, format: .number).keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text("g").foregroundStyle(Color.inkMuted)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            if let s = item.servingGrams { chip("1 serve (\(NumberText.format(s)) g)") { grams = s }; chip("2 serves") { grams = s * 2 } }
                            chip("50 g") { grams = 50 }; chip("100 g") { grams = 100 }; chip("150 g") { grams = 150 }; chip("200 g") { grams = 200 }
                        }
                    }
                }
                Section("When") {
                    Picker("Meal", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.label).tag($0) } }
                    DatePicker("Eaten at", selection: $eatenAt)
                }
                Section { Toggle("Favourite", isOn: $favourite) }
            }
            .themedList()
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.fontWeight(.semibold).disabled(grams <= 0)
                        .accessibilityIdentifier("addFoodConfirm")
                }
            }
        }
        .onAppear {
            grams = item.defaultGrams
            slot = meal
            // Logging another day: keep that day, at the current time.
            if !Calendar.current.isDateInToday(day) {
                let t = Calendar.current.dateComponents([.hour, .minute], from: .now)
                eatenAt = Calendar.current.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: day) ?? day
            }
            favourite = saved.first { $0.foodId == item.id }?.isFavourite ?? false
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.ink)
            Text(l).font(.caption2).foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(t, action: a).font(.footnote.weight(.semibold)).buttonStyle(.bordered).tint(Color.gold)
    }

    private func save() {
        context.insert(FoodEntry(item: item, grams: grams, meal: slot, source: source, eatenAt: eatenAt))
        let s = saved.first { $0.foodId == item.id } ?? {
            let n = SavedFood(item: item, isCustom: source == .manual)
            context.insert(n)
            return n
        }()
        s.lastUsed = .now
        s.useCount += 1
        s.isFavourite = favourite
        try? context.save()
        dismiss()
        onDone()
    }
}

struct EditEntrySheet: View {
    @Bindable var entry: FoodEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var grams: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.name).font(.title3.weight(.semibold))
                    TextField("Grams", value: $grams, format: .number).keyboardType(.decimalPad)
                    Picker("Meal", selection: Binding(get: { entry.meal }, set: { entry.mealRaw = $0.rawValue })) {
                        ForEach(MealSlot.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Eaten at", selection: $entry.eatenAt)
                }
                Section {
                    LabeledContent("Logged", value: entry.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Source", value: entry.source.rawValue.capitalized)
                }
                Section {
                    Button("Delete", role: .destructive) { context.delete(entry); try? context.save(); dismiss() }
                }
            }
            .themedList()
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if grams > 0, entry.grams > 0, grams != entry.grams {
                            let f = grams / entry.grams
                            entry.kcal *= f; entry.protein *= f; entry.carbs *= f; entry.fat *= f; entry.fibre *= f
                            entry.grams = grams
                        }
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear { grams = entry.grams }
        }
    }
}

struct CustomFoodForm: View {
    let onSave: (FoodItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var barcode: String
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var fibre: Double?
    @State private var serving: Double?
    @State private var scanningBarcode = false
    @State private var reading = false
    @State private var note: String?

    init(barcode: String? = nil, onSave: @escaping (FoodItem) -> Void) {
        self.onSave = onSave
        _barcode = State(initialValue: barcode ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PackPhotoButton(title: "Photo of the barcode", systemImage: "barcode.viewfinder") { image in
                        Task { await readBarcode(image) }
                    }
                    PackPhotoButton(title: "Photo of the nutrition panel", systemImage: "text.viewfinder") { image in
                        Task { await readPanel(image) }
                    }
                    .accessibilityIdentifier("panelPhoto")
                    if reading { HStack { ProgressView(); Text("Reading the photo").foregroundStyle(.secondary) } }
                    if let note { Text(note).font(.footnote).foregroundStyle(Color.gold) }
                } header: { Text("Fill it in from the pack") } footer: {
                    Text("The photo is read on your phone and not kept. Always check the numbers against the label before saving.")
                }
                Section { TextField("Name", text: $name); TextField("Brand (optional)", text: $brand) }
                Section {
                    HStack {
                        TextField("Barcode (optional)", text: $barcode).keyboardType(.numberPad)
                        Button("Scan") { scanningBarcode = true }.buttonStyle(.bordered)
                    }
                } footer: {
                    Text("With a barcode saved, scanning this product again finds it straight away.")
                }
                Section("Per 100 g, from the label") {
                    field("Energy (kcal)", $kcal); field("Protein (g)", $protein)
                    field("Carbohydrate (g)", $carbs); field("Fat (g)", $fat); field("Fibre (g, optional)", $fibre)
                }
                Section { field("Serving size (g, optional)", $serving) } footer: {
                    Text("Australian labels list kJ: divide by 4.184 for kcal.")
                }
            }
            .themedList()
            .navigationTitle("Create food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let code = barcode.trimmingCharacters(in: .whitespaces)
                        onSave(FoodItem(id: code.isEmpty ? "custom-" + UUID().uuidString : code, name: name, brand: brand.isEmpty ? nil : brand,
                                        barcode: code.isEmpty ? nil : code,
                                        per100: Per100(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0, fibre: fibre ?? 0),
                                        servingGrams: serving, servingLabel: serving.map { "\(NumberText.format($0)) g" }))
                    }
                    .disabled(name.isEmpty || kcal == nil)
                    .accessibilityIdentifier("saveFood")
                }
            }
            .fullScreenCover(isPresented: $scanningBarcode) {
                BarcodeScanner { code in barcode = code; scanningBarcode = false } onCancel: { scanningBarcode = false }
            }
        }
    }

    private func readBarcode(_ image: UIImage) async {
        reading = true; defer { reading = false }
        if let code = await PanelScanner.barcodes(in: image).first {
            barcode = code
            note = "Barcode \(code) read."
        } else {
            note = "Couldn't find a barcode in that photo. Try again closer and in good light, or tap Scan."
        }
    }

    private func readPanel(_ image: UIImage) async {
        reading = true; defer { reading = false }
        let r = NutritionPanel.parse(await PanelScanner.rows(in: image))
        guard r.foundAnything else {
            note = "Couldn't read the numbers. Lay the panel flat in good light and try again, or type them in."
            return
        }
        if let v = r.kcal { kcal = v }
        if let v = r.protein { protein = v }
        if let v = r.carbs { carbs = v }
        if let v = r.fat { fat = v }
        if let v = r.fibre { fibre = v }
        if let v = r.servingGrams { serving = v }
        let missing = [("energy", r.kcal), ("protein", r.protein), ("carbs", r.carbs), ("fat", r.fat)].filter { $0.1 == nil }.map(\.0)
        var text = "Filled in from the photo. Check each number against the label."
        if !r.foundBothColumns { text += " Only one column was found, so make sure it is per 100 g." }
        if !missing.isEmpty { text += " Couldn't read: \(missing.joined(separator: ", "))." }
        note = text
    }

    private func field(_ label: String, _ v: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            TextField("0", value: v, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }
}

/// A button that offers the camera or the photo library and hands back the picture.
struct PackPhotoButton: View {
    let title: String
    let systemImage: String
    let onImage: (UIImage) -> Void
    @State private var asking = false
    @State private var camera = false
    @State private var library = false
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?

    var body: some View {
        Button { asking = true } label: { Label(title, systemImage: systemImage) }
            .confirmationDialog(title, isPresented: $asking, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take a photo") { camera = true } }
                Button("Choose from photos") { library = true }
            }
            .fullScreenCover(isPresented: $camera) { CameraPicker(image: $image).ignoresSafeArea() }
            .photosPicker(isPresented: $library, selection: $item, matching: .images)
            .onChange(of: image) { _, new in if let new { onImage(new); image = nil } }
            .onChange(of: item) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: data) { onImage(img) }
                    item = nil
                }
            }
    }
}

// MARK: - Barcode scanner (VisionKit live text, on-device)

struct BarcodeScanner: View {
    let onCode: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerRepresentable(onCode: onCode).ignoresSafeArea()
            } else {
                Color.night.ignoresSafeArea()
                ContentUnavailableView("Scanner unavailable", systemImage: "barcode.viewfinder",
                                       description: Text("Barcode scanning needs a recent iPhone and camera access. Allow it in Settings › Steady Strength, or search by name."))
            }
            HStack {
                Text("Point at a barcode").font(.headline).foregroundStyle(.white)
                Spacer()
                Button("Cancel", action: onCancel).font(.headline).foregroundStyle(Color.gold)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                           qualityLevel: .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let b) = item, let code = b.payloadStringValue {
                    done = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    scanner.stopScanning()
                    onCode(code)
                    return
                }
            }
        }
    }
}
