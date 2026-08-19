//
//  AddEntryView.swift
//  SkyLine
//
//  View for adding new timeline entries to trips.
//  Built entirely from the form primitives in AddTripView.swift.
//

import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers

struct AddEntryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss

    let tripId: String

    @State private var selectedEntryType: TripEntryType = .food
    @State private var title = ""
    @State private var content = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var selectedDocuments: [URL] = []
    @State private var timestamp = Date()

    @State private var isCreating = false
    @State private var error: String?

    // Destination search
    @State private var destination = ""
    @State private var selectedDestination: DestinationSuggestion?
    @FocusState private var isDestinationFieldFocused: Bool

    @StateObject private var searchManager: DestinationSearchManager

    // Get trip for region biasing
    private var trip: Trip? {
        tripStore.trips.first { $0.id == tripId }
    }

    init(tripId: String) {
        self.tripId = tripId

        // Initialize search manager without region bias initially
        // We'll set it in onAppear when we have access to tripStore
        _searchManager = StateObject(wrappedValue: DestinationSearchManager(regionBias: nil))
    }

    private var isValidEntry: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let theme = themeManager.currentTheme

        return ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FormScreenHeader(title: "New Entry") { dismiss() }

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        detailsSection
                        whereSection
                        notesSection
                        attachmentsSection

                        if let error = error {
                            FormErrorBanner(message: error)
                        }

                        submitSection
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .skylineScrollEdges()
            }
        }
        .environment(\.colorScheme, theme.colorScheme)
        .onAppear {
            // Set region bias for search based on trip destination
            if let trip = trip, let coordinate = trip.coordinate {
                // Create a region centered on the trip destination
                // Span covers roughly 300km radius (good for city + surrounding areas)
                let region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 300_000,  // 300km
                    longitudinalMeters: 300_000
                )
                searchManager.regionBias = region
                print("🗺️ Entry search biased to \(trip.destination) region")
            }
        }
        .onChange(of: selectedPhotos) { _, newItems in
            loadImages(from: newItems)
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "The moment")

            FormField(
                title: "Title",
                text: $title,
                placeholder: "What happened?",
                isRequired: true,
                icon: "pencil"
            )

            entryTypeField
            timestampField
        }
    }

    private var entryTypeField: some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: "Activity type")

            Menu {
                ForEach(TripEntryType.allCases, id: \.self) { type in
                    Button {
                        selectedEntryType = type
                    } label: {
                        Label {
                            Text(type.displayName)
                        } icon: {
                            Text(type.emoji)
                        }
                    }
                }
            } label: {
                FormFieldRow {
                    // The entry type already ships an emoji. That, plus the name, is
                    // the whole signal — the nine unmanaged system hues this row used
                    // to carry competed with the three verdict colours that mean
                    // something, and none of them survived the light/dark flip.
                    Text(selectedEntryType.emoji)
                        .appFont(.headline, lineLimit: .exactly(1))

                    Text(selectedEntryType.displayName)
                        .appFont(.body, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppTypography.mono(.caption, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Activity type"))
            .accessibilityValue(Text(selectedEntryType.displayName))
        }
    }

    private var timestampField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: "When")

            FormFieldRow(icon: "clock") {
                DatePicker(
                    "Date and time",
                    selection: $timestamp,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(themeManager.currentTheme.colors.primary)
                .accessibilityLabel(Text("Date and time"))

                Spacer(minLength: 0)
            }
        }
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Where")

            DestinationSection(
                destination: $destination,
                selectedDestination: $selectedDestination,
                isDestinationFieldFocused: _isDestinationFieldFocused,
                searchManager: searchManager
            )
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Notes")

            FormField(
                title: "How was it?",
                text: $content,
                placeholder: "Optional",
                isMultiline: true,
                icon: "note.text"
            )
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Attachments")

            PhotosSection(
                selectedPhotos: $selectedPhotos,
                selectedImages: $selectedImages
            )

            DocumentsSection(
                selectedDocuments: $selectedDocuments
            )
        }
    }

    private var submitSection: some View {
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.sm) {
                FormPrimaryButton(
                    title: "Add to Timeline",
                    systemImage: selectedEntryType.systemImage,
                    busyTitle: "Creating…",
                    isBusy: isCreating,
                    isEnabled: isValidEntry
                ) {
                    createEntry()
                }

                FormSecondaryButton(title: "Cancel") {
                    dismiss()
                }
            }
        }
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Helper Methods

    private func getPlaceholderTitle() -> String {
        switch selectedEntryType {
        case .food: return "Amazing ramen in Shibuya"
        case .activity: return "Morning hike to the summit"
        case .sightseeing: return "Tokyo Skytree observation deck"
        case .accommodation: return "Cozy ryokan in Kyoto"
        case .transportation: return "Bullet train to Osaka"
        case .shopping: return "Vintage finds in Harajuku"
        case .note: return "Random thoughts about the trip"
        case .photo: return "Beautiful sunset view"
        case .flight: return "Flight AA1234 to Tokyo"
        }
    }

    private func getPlaceholderContent() -> String {
        switch selectedEntryType {
        case .food: return "The broth was incredibly rich and flavorful. Best ramen I've ever had!"
        case .activity: return "Challenging but rewarding climb. The views from the top were breathtaking."
        case .sightseeing: return "360-degree views of the entire city. You can see for miles in every direction."
        case .accommodation: return "Traditional Japanese room with tatami mats. So peaceful and authentic."
        case .transportation: return "Smooth and fast ride. Amazing how quiet it is at 200 mph."
        case .flight: return "Great flight with amazing views. Smooth takeoff and landing."
        case .shopping: return "Found some unique pieces that you can't get anywhere else."
        case .note: return "Just some thoughts about this incredible experience..."
        case .photo: return "Had to capture this amazing moment."
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) {
        selectedImages = []

        for item in items {
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImages.append(image)
                    }
                }
            }
        }
    }

    private func createEntry() {
        guard isValidEntry else { return }

        isCreating = true
        error = nil

        Task {
            // Create image URLs (in a real app, you'd upload to CloudKit first)
            let imageURLs: [String] = [] // Placeholder - implement image upload

            let entry = TripEntry(
                tripId: tripId,
                timestamp: timestamp,
                entryType: selectedEntryType,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                imageURLs: imageURLs,
                latitude: selectedDestination?.latitude,
                longitude: selectedDestination?.longitude,
                locationName: selectedDestination?.displayName
            )

            let result = await tripStore.addEntry(entry)

            await MainActor.run {
                isCreating = false

                switch result {
                case .success:
                    dismiss()
                case .failure(let tripError):
                    error = tripError.localizedDescription
                }
            }
        }
    }
}

// MARK: - Attachment Add Row
/// The "add something" affordance shared by the photo and document sections:
/// a recessed well with a primary-ink glyph. Deliberately the same object as a
/// form field, because that is what it is — an empty slot.
struct AttachmentAddRow: View {
    @EnvironmentObject var themeManager: ThemeManager

    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        let theme = themeManager.currentTheme

        return FormFieldRow {
            Image(systemName: systemImage)
                .font(AppTypography.mono(.title3, weight: .medium))
                .foregroundStyle(theme.colors.primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)

                Text(subtitle)
                    .appFont(.placeMeta, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(AppTypography.mono(.caption, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Remove Badge
/// The little "x" that sits on a photo thumbnail. A photo has no theme, so this
/// cannot borrow contrast from the backdrop: it is an opaque two-tone glyph —
/// `text` ink inside a `surface` disc — which is legible on any image in either
/// palette without a single literal colour.
struct RemoveBadge: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.currentTheme

        return Image(systemName: "xmark.circle.fill")
            .font(AppTypography.mono(.title3, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(theme.colors.text, theme.colors.surface)
    }
}

// MARK: - Photos Section
struct PhotosSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var selectedImages: [UIImage]

    @ScaledMetric(relativeTo: .body) private var thumbHeight: CGFloat = 86

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm + 4) {
            if selectedImages.isEmpty {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    AttachmentAddRow(
                        systemImage: "photo.badge.plus",
                        title: "Add Photos",
                        subtitle: "Up to five, optional"
                    )
                }
                .buttonStyle(.plain)
            } else {
                photoGrid
            }
        }
    }

    private var photoGrid: some View {
        let theme = themeManager.currentTheme

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 3),
            spacing: AppSpacing.sm
        ) {
            ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: thumbHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))

                    Button {
                        removeImage(at: index)
                    } label: {
                        RemoveBadge()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove photo \(index + 1)"))
                    .offset(x: AppSpacing.xs + 2, y: -(AppSpacing.xs + 2))
                }
            }

            // Add more photos button
            if selectedImages.count < 5 {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5 - selectedImages.count,
                    matching: .images
                ) {
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(theme.colors.surface)
                        .frame(height: thumbHeight)
                        .overlay(
                            Image(systemName: "plus")
                                .font(AppTypography.mono(.title2, weight: .regular))
                                .foregroundStyle(theme.colors.textSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .stroke(theme.colors.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add more photos"))
            }
        }
    }

    private func removeImage(at index: Int) {
        selectedImages.remove(at: index)
        if index < selectedPhotos.count {
            selectedPhotos.remove(at: index)
        }
    }
}

// MARK: - Destination Section
struct DestinationSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var destination: String
    @Binding var selectedDestination: DestinationSuggestion?
    @FocusState var isDestinationFieldFocused: Bool
    @ObservedObject var searchManager: DestinationSearchManager

    @ScaledMetric(relativeTo: .body) private var mapHeight: CGFloat = 170

    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: "Place")

            FormFieldRow(icon: "mappin", isFocused: isDestinationFieldFocused) {
                TextField("Where (optional)", text: $destination)
                    .appFont(.body, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)
                    .tint(theme.colors.primary)
                    .focused($isDestinationFieldFocused)
                    .onChange(of: destination) { _, newValue in
                        searchManager.search(for: newValue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !destination.isEmpty {
                    Button {
                        destination = ""
                        selectedDestination = nil
                        searchManager.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypography.mono(.callout))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear place"))
                }
            }

            // Search results
            if isDestinationFieldFocused && !searchManager.searchResults.isEmpty {
                searchResults
            }

            // Map preview for selected destination
            if let selectedDest = selectedDestination, !isDestinationFieldFocused {
                destinationMapPreview(for: selectedDest)
            }
        }
    }

    private var searchResults: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: 0) {
            ForEach(searchManager.searchResults, id: \.self) { result in
                Button {
                    selectDestination(result)
                } label: {
                    DestinationResultRow(title: result.title, subtitle: result.subtitle)
                }
                .buttonStyle(.plain)

                if result != searchManager.searchResults.last {
                    Rectangle()
                        .fill(theme.colors.border)
                        .frame(height: 1)
                        .padding(.leading, AppSpacing.md)
                        .accessibilityHidden(true)
                }
            }
        }
        .formFloatingPanel(theme: theme)
    }

    private func selectDestination(_ completion: MKLocalSearchCompletion) {
        Task {
            if let suggestion = await searchManager.getLocationDetails(for: completion) {
                await MainActor.run {
                    selectedDestination = suggestion
                    destination = suggestion.displayName
                    isDestinationFieldFocused = false
                    searchManager.clearSearch()
                }
            }
        }
    }

    private func destinationMapPreview(for destination: DestinationSuggestion) -> some View {
        let theme = themeManager.currentTheme
        let coordinate = CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        let shape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)

        return Map(initialPosition: .region(region)) {
            Marker(destination.displayName, coordinate: coordinate)
                .tint(theme.colors.primary)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .frame(height: mapHeight)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(shape.stroke(theme.colors.border, lineWidth: 1))
        .id("\(destination.latitude),\(destination.longitude)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map showing \(destination.displayName)"))
    }
}

// MARK: - Documents Section
struct DocumentsSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedDocuments: [URL]
    @State private var showingDocumentPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm + 4) {
            if selectedDocuments.isEmpty {
                Button {
                    showingDocumentPicker = true
                } label: {
                    AttachmentAddRow(
                        systemImage: "doc.badge.plus",
                        title: "Add Documents",
                        subtitle: "Bookings, tickets, confirmations"
                    )
                }
                .buttonStyle(.plain)
            } else {
                documentList
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            EntryDocumentPicker(selectedDocuments: $selectedDocuments)
        }
    }

    private var documentList: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(Array(selectedDocuments.enumerated()), id: \.offset) { index, documentURL in
                documentRow(index: index, url: documentURL)
            }

            Button {
                showingDocumentPicker = true
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "plus")
                    Text("Add More Documents")
                }
                .appFont(.verdictLabel, lineLimit: .exactly(1))
                .foregroundStyle(themeManager.currentTheme.colors.primary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(themeManager.currentTheme.colors.primary)
        }
    }

    private func documentRow(index: Int, url: URL) -> some View {
        let theme = themeManager.currentTheme

        return FormFieldRow(icon: getDocumentIcon(for: url)) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(url.lastPathComponent)
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)

                Text(formatFileSize(url: url))
                    .appFont(.placeMeta, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                removeDocument(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTypography.mono(.title3))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(url.lastPathComponent)"))
        }
    }

    private func getDocumentIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.text.fill"
        case "jpg", "jpeg", "png", "heic":
            return "photo.fill"
        case "zip":
            return "doc.zipper"
        default:
            return "doc.fill"
        }
    }

    private func formatFileSize(url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return ""
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    private func removeDocument(at index: Int) {
        selectedDocuments.remove(at: index)
    }
}

// MARK: - Entry Document Picker
struct EntryDocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedDocuments: [URL]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image, .text, .zip], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: EntryDocumentPicker

        init(_ parent: EntryDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.selectedDocuments.append(contentsOf: urls)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

#Preview {
    AddEntryView(tripId: "sample-trip")
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}
