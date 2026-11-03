import SwiftUI
import SwiftData
import SafariServices
import AVKit
import PhotosUI
import SteadyCore

/// Form cues, muscles, equipment and today's swaps for one exercise.
/// Video playback and "Add my video" arrive in Phase 2; until a curated link
/// or your own clip exists, "Find a demo video" opens a YouTube search in an
/// in-app Safari view (nothing is downloaded or re-hosted).
struct ExerciseSheet: View {
    let exerciseId: String
    var slot: ExerciseSlot? = nil
    var maxDifficulty: Int = 3
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [TrainingPlan]
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            if let content = store.content, let ex = content.library[exerciseId] {
                let available = Set(plans.first?.equipment ?? content.equipment.profile("full_gym")?.equipment ?? [])
                let choice = Substitution.choose(exerciseId, library: content.library, available: available,
                                                 maxDifficulty: maxDifficulty, slotAlternatives: slot?.alternativeIds ?? [])
                List {
                    Section("How to do it") {
                        Text(ex.cues)
                        if let note = slot?.notes, !note.isEmpty, note != ex.cues {
                            Text(note).foregroundStyle(.secondary)
                        }
                        if ex.contraindicationReviewFlag == true {
                            Label("Advanced movement. Check with a qualified coach if you have any pain or past injury. Stop if anything hurts, and use an easier option.",
                                  systemImage: "exclamationmark.shield")
                                .font(.footnote).foregroundStyle(Color.gold)
                        }
                        if let tip = ex.advancedTip {
                            Label(tip, systemImage: "arrow.left.and.right")
                                .font(.footnote).foregroundStyle(Color.inkMuted)
                        }
                        Button {
                            showSearch = true
                        } label: {
                            Label("Watch technique (Jeff Nippard on YouTube)", systemImage: "play.rectangle")
                        }
                        .accessibilityHint("Opens a YouTube search for Jeff Nippard's technique video in Safari")
                    }
                    MyClipSection(exerciseId: exerciseId)
                    Section("Works") {
                        Text(ex.primaryMuscles.map(Self.muscleName).joined(separator: ", "))
                        if !ex.secondaryMuscles.isEmpty {
                            Text("Also: " + ex.secondaryMuscles.map(Self.muscleName).joined(separator: ", "))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Needs") {
                        if ex.equipment.isEmpty {
                            Text("No equipment")
                        } else {
                            ForEach(ex.equipment, id: \.self) { item in
                                Text(item.split(separator: "/").map { content.equipment.equipment[String($0)] ?? String($0) }
                                    .joined(separator: " or "))
                            }
                        }
                    }
                    Section {
                        if choice.id != exerciseId, let swapId = choice.id, let swap = content.library[swapId] {
                            Label("Not available with your equipment. Today: \(swap.name)", systemImage: "arrow.triangle.swap")
                        }
                        ForEach(Substitution.options(exerciseId, library: content.library, available: available,
                                                     maxDifficulty: maxDifficulty)) { alt in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alt.name)
                                Text(alt.cues).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if let text = ex.swapText {
                            Text("Coach's note: \(text)").font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Swaps with your equipment")
                    } footer: {
                        Text("Picking a swap during a workout arrives with workout logging. Each exercise keeps its own weight history.")
                    }
                }
                .themedList()
                .navigationTitle(ex.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $showSearch) {
                    SafariView(url: Self.searchURL(ex.demoSearchQuery))
                        .ignoresSafeArea()
                }
            } else {
                ContentUnavailableView("Exercise not found", systemImage: "questionmark")
            }
        }
    }

    static func muscleName(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "delts", with: "shoulders")
            .replacingOccurrences(of: "glute med", with: "side glutes")
    }

    static func searchURL(_ query: String) -> URL {
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return c.url!
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}


/// "My clip": record or pick a short video of your own technique and play it back from here.
struct MyClipSection: View {
    let exerciseId: String
    @State private var clipURL: URL?
    @State private var picked: PhotosPickerItem?
    @State private var player: AVPlayer?
    @State private var message: String?

    var body: some View {
        Section {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            PhotosPicker(selection: $picked, matching: .videos) {
                Label(clipURL == nil ? "Add my own clip" : "Replace my clip", systemImage: "video.badge.plus")
            }
            .accessibilityIdentifier("addClip")
            if clipURL != nil {
                Button(role: .destructive) {
                    ClipStore.delete(for: exerciseId)
                    load()
                } label: { Label("Remove my clip", systemImage: "trash") }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Color.inkMuted) }
        } header: { Text("My clip") } footer: {
            Text("Kept on this phone only, never uploaded.")
        }
        .onAppear(perform: load)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let video = try await item.loadTransferable(type: PickedVideo.self) else { message = "Couldn't read that video."; return }
                    try ClipStore.save(video.url, for: exerciseId)
                    message = nil
                    load()
                } catch {
                    message = "Couldn't save that video."
                }
                picked = nil
            }
        }
    }

    private func load() {
        clipURL = ClipStore.url(for: exerciseId)
        player = clipURL.map { AVPlayer(url: $0) }
    }
}
