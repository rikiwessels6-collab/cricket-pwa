import SwiftUI
import SwiftData
import SteadyCore

/// Add or edit an exercise of your own.
struct CustomExerciseForm: View {
    var editing: CustomExercise? = nil
    var onSaved: ((String) -> Void)? = nil
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var primary = "chest"
    @State private var secondary = ""
    @State private var kind = "dumbbells"
    @State private var loadable = true
    @State private var unilateral = false
    @State private var timed = false
    @State private var loaded = false

    private var muscles: [String] { store.content?.muscleIds ?? [] }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("For example, Cable crunch", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("customName")
                }
                Section {
                    Picker("Main muscle", selection: $primary) {
                        ForEach(muscles, id: \.self) { Text(VolumeReport.prettyName($0)).tag($0) }
                    }
                    Picker("Also works", selection: $secondary) {
                        Text("Nothing in particular").tag("")
                        ForEach(muscles.filter { $0 != primary }, id: \.self) { Text(VolumeReport.prettyName($0)).tag($0) }
                    }
                } header: { Text("Muscles") } footer: {
                    Text("Used for your weekly volume. The main muscle gets full credit for each set, the other half.")
                }
                Section("Done with") {
                    Picker("Equipment", selection: $kind) {
                        ForEach(CustomExercise.kinds, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    Toggle("Track weight", isOn: $loadable)
                    Toggle("One side at a time", isOn: $unilateral)
                    Toggle("Timed hold (not counted as volume)", isOn: $timed)
                }
            }
            .navigationTitle(editing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(trimmed.isEmpty || muscles.isEmpty)
                        .accessibilityIdentifier("saveCustom")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = editing {
                    name = e.name; primary = e.primaryMuscle; secondary = e.secondaryMuscle ?? ""
                    kind = e.kind; loadable = e.loadable; unilateral = e.unilateral; timed = e.timed
                } else if let first = muscles.first {
                    primary = muscles.contains("chest") ? "chest" : first
                }
            }
            .onChange(of: kind) { _, new in if editing == nil { loadable = new != "bodyweight" } }
        }
    }

    private func save() {
        let second: String? = secondary.isEmpty || secondary == primary ? nil : secondary
        let id: String
        if let e = editing {
            e.name = trimmed; e.primaryMuscle = primary; e.secondaryMuscle = second
            e.kind = kind; e.loadable = loadable; e.unilateral = unilateral; e.timed = timed
            id = e.exerciseId
        } else {
            let e = CustomExercise(name: trimmed, primaryMuscle: primary, secondaryMuscle: second, kind: kind,
                                   loadable: loadable, unilateral: unilateral, timed: timed)
            context.insert(e)
            id = e.exerciseId
        }
        try? context.save()
        if let all = try? context.fetch(FetchDescriptor<CustomExercise>()) { store.setCustom(all.map(\.asExercise)) }
        onSaved?(id)
        dismiss()
    }
}

/// Pick any exercise (built-in or your own) to add to an open workout.
struct ExercisePicker: View {
    let onPick: (String) -> Void
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var muscle = ""
    @State private var creating = false

    private var results: [Exercise] {
        guard let lib = store.content?.library.values else { return [] }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return lib.filter { e in
            (muscle.isEmpty || e.primaryMuscles.first == muscle)
                && (q.isEmpty || e.name.lowercased().contains(q) || e.aliases.contains { $0.lowercased().contains(q) })
        }
        .sorted { ($0.isCustom ? 0 : 1, $0.name) < ($1.isCustom ? 0 : 1, $1.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { creating = true } label: { Label("Create my own exercise", systemImage: "plus.circle") }
                        .accessibilityIdentifier("createCustom")
                    Picker("Muscle", selection: $muscle) {
                        Text("All muscles").tag("")
                        ForEach(store.content?.muscleIds ?? [], id: \.self) { Text(VolumeReport.prettyName($0)).tag($0) }
                    }
                }
                Section {
                    ForEach(results) { e in
                        Button { onPick(e.id); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(e.name).foregroundStyle(.primary)
                                    if e.isCustom { Chip(text: "MINE", prominent: false) }
                                }
                                Text(e.primaryMuscles.map(VolumeReport.prettyName).joined(separator: ", "))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("pick-\(e.id)")
                    }
                }
            }
            .themedList()
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $creating) {
                CustomExerciseForm { id in onPick(id); dismiss() }
            }
        }
    }
}

/// Your own exercises, in Settings.
struct MyExercisesView: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomExercise.name) private var mine: [CustomExercise]
    @State private var editing: CustomExercise?
    @State private var creating = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                if mine.isEmpty {
                    Text("Exercises you add yourself appear here. Add one from an open workout, or tap New exercise.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(mine) { e in
                    Button { editing = e } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).foregroundStyle(.primary)
                            Text(VolumeReport.prettyName(e.primaryMuscle)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { remove(mine[i]) }
                }
            } footer: {
                if let message { Text(message) } else { Text("An exercise you have already used in a workout can't be deleted, so your history stays complete. You can rename it.") }
            }
        }
        .themedList()
        .navigationTitle("My exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("New exercise") { creating = true } }
        }
        .sheet(isPresented: $creating) { CustomExerciseForm() }
        .sheet(item: $editing) { CustomExerciseForm(editing: $0) }
    }

    private func remove(_ e: CustomExercise) {
        let id = e.exerciseId
        let used = (try? context.fetchCount(FetchDescriptor<SetLog>(predicate: #Predicate { $0.exerciseId == id }))) ?? 0
        guard used == 0 else {
            message = "\(e.name) is in your workout history, so it stays. You can rename it instead."
            return
        }
        context.delete(e)
        try? context.save()
        if let all = try? context.fetch(FetchDescriptor<CustomExercise>()) { store.setCustom(all.map(\.asExercise)) }
        message = nil
    }
}
