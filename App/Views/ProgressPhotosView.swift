import SwiftUI
import SwiftData
import PhotosUI
import SteadyCore

/// Front, side and rear photos over time. They stay inside the app behind your lock.
struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @Query private var settings: [AppSettings]
    @State private var adding = false
    @State private var comparing = false
    @State private var viewing: ProgressPhoto?

    private var consented: Bool { settings.first?.consents[DataType.photos.rawValue] != nil }

    private var days: [Date] {
        Array(Set(photos.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >)
    }

    var body: some View {
        List {
            Section {
                Toggle("Keep progress photos in this app", isOn: Binding(
                    get: { consented },
                    set: { on in settings.first?.consents[DataType.photos.rawValue] = on ? .now : nil }))
                    .accessibilityIdentifier("photosConsent")
            } footer: {
                Text("Photos are stored only inside Steady Strength, locked when your phone is locked. They aren't added to your Photos library, aren't analysed and never leave your phone.")
            }
            if consented {
                Section {
                    Button { adding = true } label: { Label("Add photos", systemImage: "camera") }
                        .accessibilityIdentifier("addPhotos")
                    if days.count >= 2 {
                        Button { comparing = true } label: { Label("Compare two dates", systemImage: "rectangle.split.2x1") }
                    }
                }
                if photos.isEmpty {
                    Section { Text("Take front, side and rear photos in the same spot, light and clothing each time. Every few weeks is plenty.")
                        .font(.footnote).foregroundStyle(Color.inkMuted) }
                }
                ForEach(days, id: \.self) { day in
                    let dayPhotos = photos.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                    Section(day.formatted(date: .long, time: .omitted)) {
                        HStack(spacing: 10) {
                            ForEach(PhotoAngle.allCases) { angle in
                                if let photo = dayPhotos.first(where: { $0.angle == angle }) {
                                    Button { viewing = photo } label: { PhotoThumb(fileName: photo.fileName, label: angle.label) }
                                        .buttonStyle(.plain)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Progress photos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { AddPhotosSheet() }
        .sheet(isPresented: $comparing) { PhotoCompareView(photos: photos, days: days) }
        .sheet(item: $viewing) { photo in PhotoViewer(photo: photo) }
    }
}

struct PhotoThumb: View {
    let fileName: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            if let image = PhotoStore.thumbnail(fileName) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 130).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.surfaceRaised).frame(height: 130)
            }
            Text(label).font(.caption2).foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(label) photo")
    }
}

/// Add up to three photos for one day.
struct AddPhotosSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var images: [PhotoAngle: UIImage] = [:]
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section { DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date) }
                ForEach(PhotoAngle.allCases) { angle in
                    Section {
                        PhotoSlot(angle: angle, image: Binding(get: { images[angle] }, set: { images[angle] = $0 }))
                    }
                }
                if failed { Section { Text("Couldn't save one of the photos. Try again.").foregroundStyle(Color.gold) } }
            }
            .themedList()
            .navigationTitle("Add photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(images.isEmpty)
                        .accessibilityIdentifier("savePhotos")
                }
            }
        }
    }

    private func save() {
        for angle in PhotoAngle.allCases {
            guard let image = images[angle] else { continue }
            do {
                let name = try PhotoStore.save(image)
                context.insert(ProgressPhoto(date: date, angle: angle, fileName: name))
            } catch {
                failed = true
                return
            }
        }
        try? context.save()
        dismiss()
    }
}

private struct PhotoSlot: View {
    let angle: PhotoAngle
    @Binding var image: UIImage?
    @State private var item: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(angle.label).font(.headline)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label(image == nil ? "Take photo" : "Retake", systemImage: "camera") }
                        .buttonStyle(.bordered)
                }
                PhotosPicker(selection: $item, matching: .images) { Label("Choose", systemImage: "photo") }
                    .buttonStyle(.bordered)
                if image != nil {
                    Button("Remove", role: .destructive) { image = nil }.buttonStyle(.bordered)
                }
            }
            .font(.footnote)
        }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(image: $cameraImage).ignoresSafeArea() }
        .onChange(of: cameraImage) { _, new in
            if let new { image = new; cameraImage = nil }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let picked = UIImage(data: data) { image = picked }
                item = nil
            }
        }
    }
}

struct PhotoViewer: View {
    let photo: ProgressPhoto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let image = PhotoStore.load(photo.fileName) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("This photo can't be opened.").foregroundStyle(Color.inkMuted)
                }
            }
            .background(Color.night.ignoresSafeArea())
            .navigationTitle("\(photo.angle.label), \(photo.date.formatted(date: .abbreviated, time: .omitted))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) { Button("Delete", role: .destructive) { confirmDelete = true } }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    PhotoStore.delete(photo.fileName)
                    context.delete(photo)
                    try? context.save()
                    dismiss()
                }
            } message: { Text("It's removed from this phone and can't be recovered.") }
        }
    }
}

/// Two dates side by side, angle by angle.
struct PhotoCompareView: View {
    let photos: [ProgressPhoto]
    let days: [Date]
    @Environment(\.dismiss) private var dismiss
    @State private var before: Date
    @State private var after: Date

    init(photos: [ProgressPhoto], days: [Date]) {
        self.photos = photos
        self.days = days
        _before = State(initialValue: days.last ?? .now)
        _after = State(initialValue: days.first ?? .now)
    }

    private func photo(_ day: Date, _ angle: PhotoAngle) -> ProgressPhoto? {
        photos.first { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.angle == angle }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Before", selection: $before) {
                        ForEach(days, id: \.self) { Text($0.formatted(date: .abbreviated, time: .omitted)).tag($0) }
                    }
                    Picker("After", selection: $after) {
                        ForEach(days, id: \.self) { Text($0.formatted(date: .abbreviated, time: .omitted)).tag($0) }
                    }
                }
                ForEach(PhotoAngle.allCases) { angle in
                    if let b = photo(before, angle), let a = photo(after, angle) {
                        Section(angle.label) {
                            HStack(spacing: 10) {
                                PhotoThumb(fileName: b.fileName, label: "Before")
                                PhotoThumb(fileName: a.fileName, label: "After")
                            }
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
