import SwiftUI
import SwiftData
import SteadyCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ContentStore.self) private var store
    @Query private var settings: [AppSettings]
    @Query private var profiles: [UserProfile]
    @Query private var plans: [TrainingPlan]
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            Form {
                if let p = profiles.first {
                    Section("You") {
                        LabeledContent("Name", value: p.name)
                        LabeledContent("Age", value: "\(p.age)")
                        Stepper(value: Binding(get: { p.weightKg }, set: { p.weightKg = $0 }), in: 35...250, step: 0.5) {
                            LabeledContent("Weight", value: String(format: "%.1f kg", p.weightKg))
                        }
                        LabeledContent("Goal", value: p.goal.label)
                    }
                }
                if let plan = plans.first, let content = store.content {
                    Section {
                        LabeledContent("Program", value: content.program(plan.programId)?.name ?? plan.programId)
                        Picker("Equipment", selection: Binding(
                            get: { plan.equipmentProfileId },
                            set: { id in
                                plan.equipmentProfileId = id
                                if let prof = content.equipment.profile(id) { plan.equipment = prof.equipment }
                            })) {
                            ForEach(content.equipment.profiles) { Text($0.name).tag($0.id) }
                        }
                    } header: { Text("Training") } footer: {
                        Text("Change equipment when you're somewhere different, such as a hotel; exercises are swapped automatically.")
                    }
                }
                if let s = settings.first {
                    Section("Security") {
                        Toggle("Lock with \(AppLock.biometryName)", isOn: Binding(get: { s.lockEnabled }, set: { s.lockEnabled = $0 }))
                            .accessibilityIdentifier("lockToggle")
                        Picker("Lock after", selection: Binding(get: { s.lockTimeoutSeconds }, set: { s.lockTimeoutSeconds = $0 })) {
                            ForEach(LockPolicy.timeoutChoices, id: \.seconds) { Text($0.label).tag($0.seconds) }
                        }
                        .disabled(!s.lockEnabled)
                    }
                }
                Section("Privacy") {
                    NavigationLink("Privacy policy") { PrivacyPolicyView() }
                    if let s = settings.first {
                        NavigationLink("What the app keeps") { ConsentList(settings: s) }
                    }
                    Button("Export my data") {
                        do { exportURL = try DataExport.write(context) } catch { exportError = error.localizedDescription }
                    }
                    if let url = exportURL {
                        ShareLink(item: url) { Label("Share export file", systemImage: "square.and.arrow.up") }
                    }
                    Button("Erase all my data", role: .destructive) { confirmErase = true }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                    Text("Programs by RW Fitness. Exercise data compiled for this app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Erase everything?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase all my data", role: .destructive) {
                    try? Persistence.eraseAll(context)
                    context.insert(AppSettings())
                    try? context.save()
                }
            } message: {
                Text("Deletes your profile, plan, targets and settings from this phone. This can't be undone. Export first if you want a copy.")
            }
            .alert("Export failed", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }
}

struct ConsentList: View {
    @Bindable var settings: AppSettings
    var body: some View {
        Form {
            ForEach(DataType.allCases) { type in
                Toggle(isOn: Binding(
                    get: { settings.consents[type.rawValue] != nil },
                    set: { on in settings.consents[type.rawValue] = on ? .now : nil })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.title)
                        Text(type.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .disabled(type.required || type == .appleHealth)
            }
        }
        .navigationTitle("What the app keeps")
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Privacy policy").font(.title.bold())
                    Text("Last updated: November 2026").foregroundStyle(.secondary)
                    Text("Steady Strength is a personal training, nutrition and check-in app. This policy explains what it keeps and where.")
                    heading("What's stored, and where")
                    Text("Your profile, training plan and history, food log, targets, check-ins, measurements and progress photos are stored only on your iPhone, in the app's own storage, encrypted by iOS. There is no Steady Strength account and no Steady Strength server.")
                    heading("What leaves your phone")
                    Text("• Barcode lookups (when food logging arrives) send only the barcode number to Open Food Facts to find the product.\n• Demo video searches open YouTube in Safari; YouTube's own privacy policy applies there.\n• If you later turn on iCloud sync, your data is stored in your own iCloud account, encrypted by Apple.\n• If you connect Strava, the app reads your activities from Strava.\nNothing else is sent anywhere, and nothing is shared without you choosing to share it.")
                }
                Group {
                    heading("Apple Health")
                    Text("If you allow it, the app reads and writes the Health data you approve. Health data is never used for advertising, sold, or shared with third parties.")
                    heading("Photos and Face ID")
                    Text("Progress photos stay inside the app behind the lock and are never analysed. Face ID is handled entirely by iOS; the app never receives face data.")
                    heading("Your choices")
                    Text("You can change what the app keeps in Settings › What the app keeps, export everything as a file, or erase all your data at any time. Deleting the app also deletes its data from the phone.")
                    heading("Sensitive information")
                    Text("Health information is sensitive information under the Australian Privacy Act 1988. Because it stays on your device and is not collected by us, we do not hold it.")
                    heading("Contact")
                    Text("Questions: contact RW Fitness.")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heading(_ s: String) -> some View { Text(s).font(.headline).padding(.top, 4) }
}
