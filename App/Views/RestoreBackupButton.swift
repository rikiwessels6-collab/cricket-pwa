import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Picks a Steady Strength backup file (from Export my data) and restores it.
struct RestoreBackupButton: View {
    var title = "Restore from a backup"
    /// Ask first, because restoring replaces what is on this phone. Not needed during first-time setup.
    var confirm = true
    @Environment(\.modelContext) private var context
    @State private var askFirst = false
    @State private var picking = false
    @State private var result: String?

    var body: some View {
        Button(title) { if confirm { askFirst = true } else { picking = true } }
            .accessibilityIdentifier("restoreBackup")
            .confirmationDialog("Restore from a backup?", isPresented: $askFirst, titleVisibility: .visible) {
                Button("Choose a backup file", role: .destructive) { picking = true }
            } message: {
                Text("This replaces your profile, plan, workouts, food and check-ins with the ones in the file. Progress photos already on this phone are kept.")
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { picked in
                switch picked {
                case .success(let url):
                    do { result = try DataImport.restore(from: url, into: context).text }
                    catch { result = error.localizedDescription }
                case .failure(let error):
                    result = error.localizedDescription
                }
            }
            .alert("Backup", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                Button("OK") { result = nil }
            } message: { Text(result ?? "") }
    }
}
