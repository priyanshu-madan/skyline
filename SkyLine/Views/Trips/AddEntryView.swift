//
//  AddEntryView.swift
//  SkyLine
//
//  View for adding new timeline entries to trips
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
        ZStack {
            // Background
            themeManager.currentTheme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom Header
                HStack {
                    // Back button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(themeManager.currentTheme.colors.surface.opacity(0.8))
                                    .overlay(
                                        Circle()
                                            .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }

                    Spacer()

                    // Title
                    Text("New Entry")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)

                    Spacer()

                    // Spacer for balance
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 20) {
                        // Form fields
                        VStack(spacing: 16) {
                            // 1. Title
                            FormField(
                                title: "Title",
                                text: $title,
                                placeholder: "Title",
                                isRequired: true,
                                icon: "pencil"
                            )

                            // 2. Where - Destination/Location
                            DestinationSection(
                                destination: $destination,
                                selectedDestination: $selectedDestination,
                                isDestinationFieldFocused: _isDestinationFieldFocused,
                                searchManager: searchManager
                            )

                            // 3. When - Timestamp
                            HStack(spacing: 0) {
                                Image(systemName: "clock")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    .frame(width: 20, height: 20)
                                    .padding(.leading, 16)

                                DatePicker("", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .font(.system(.body, design: .monospaced, weight: .medium))
                                    .padding(.vertical, 16)
                                    .padding(.leading, 12)
                                    .padding(.trailing, 16)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                            )

                            // 4. Activity Type
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
                                HStack(spacing: 0) {
                                    Text(selectedEntryType.emoji)
                                        .font(.system(size: 20))
                                        .frame(width: 20, height: 20)
                                        .padding(.leading, 16)

                                    Text(selectedEntryType.displayName)
                                        .font(.system(.body, design: .monospaced, weight: .medium))
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                        .padding(.vertical, 16)
                                        .padding(.leading, 12)

                                    Spacer()

                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                        .padding(.trailing, 16)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                                )
                            }

                            // 5. Notes
                            FormField(
                                title: "Notes",
                                text: $content,
                                placeholder: "Notes (optional)",
                                isMultiline: true,
                                icon: "note.text"
                            )

                            // 6. Photos
                            PhotosSection(
                                selectedPhotos: $selectedPhotos,
                                selectedImages: $selectedImages
                            )

                            // 7. Documents
                            DocumentsSection(
                                selectedDocuments: $selectedDocuments
                            )
                        }
                    
                    // Create Button
                    Button {
                        createEntry()
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Creating...")
                            } else {
                                Image(systemName: selectedEntryType.systemImage)
                                Text("Add to Timeline")
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isValidEntry ? entryTypeColor : Color.gray)
                        .cornerRadius(8)
                    }
                    .disabled(!isValidEntry || isCreating)
                    
                        // Error message
                        if let error = error {
                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
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
    
    // MARK: - Helper Methods
    
    private var entryTypeColor: Color {
        switch selectedEntryType.color {
        case "orange": return .orange
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "pink": return .pink
        case "yellow": return .yellow
        default: return .gray
        }
    }
    
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

// MARK: - Photos Section
struct PhotosSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var selectedImages: [UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedImages.isEmpty {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 20, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Photos")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(themeManager.currentTheme.colors.text)

                            Text("Optional")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    .padding()
                    .background(themeManager.currentTheme.colors.surface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                VStack(spacing: 12) {
                    // Selected images grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 80)
                                    .cornerRadius(8)
                                    .clipped()
                                
                                Button {
                                    removeImage(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                        
                        // Add more photos button
                        if selectedImages.count < 5 {
                            PhotosPicker(
                                selection: $selectedPhotos,
                                maxSelectionCount: 5 - selectedImages.count,
                                matching: .images
                            ) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(themeManager.currentTheme.colors.surface)
                                    .frame(height: 80)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 24, design: .monospaced))
                                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 0) {
                    Image(systemName: "mappin")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .padding(.leading, 16)

                    TextField("Where (optional)", text: $destination)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .padding(.vertical, 16)
                        .padding(.leading, 12)
                        .focused($isDestinationFieldFocused)
                        .onChange(of: destination) { _, newValue in
                            searchManager.search(for: newValue)
                        }

                    if !destination.isEmpty {
                        Button {
                            destination = ""
                            selectedDestination = nil
                            searchManager.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        }
                        .padding(.trailing, 16)
                    } else {
                        Spacer()
                            .frame(width: 16)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                )

                // Search results
                if isDestinationFieldFocused && !searchManager.searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(searchManager.searchResults, id: \.self) { result in
                            Button {
                                selectDestination(result)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.title)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(themeManager.currentTheme.colors.text)

                                        Text(result.subtitle)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    }

                                    Spacer()
                                }
                                .padding()
                                .background(themeManager.currentTheme.colors.surface)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if result != searchManager.searchResults.last {
                                Divider()
                                    .background(themeManager.currentTheme.colors.border)
                            }
                        }
                    }
                    .background(themeManager.currentTheme.colors.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                    )
                    .padding(.top, 8)
                }

                // Map preview for selected destination
                if let selectedDest = selectedDestination, !isDestinationFieldFocused {
                    destinationMapPreview(for: selectedDest)
                        .padding(.top, 12)
                }
            }
        }
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
        let coordinate = CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )

        return Map(initialPosition: .region(region)) {
            Marker(destination.displayName, coordinate: coordinate)
                .tint(.red)
        }
        .mapStyle(.standard)
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .frame(height: 200)
        .cornerRadius(12)
        .id("\(destination.latitude),\(destination.longitude)")
    }
}

// MARK: - Documents Section
struct DocumentsSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedDocuments: [URL]
    @State private var showingDocumentPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedDocuments.isEmpty {
                Button {
                    showingDocumentPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 20, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Documents")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(themeManager.currentTheme.colors.text)

                            Text("Booking confirmations, tickets, etc.")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    .padding()
                    .background(themeManager.currentTheme.colors.surface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                VStack(spacing: 12) {
                    // Selected documents list
                    ForEach(Array(selectedDocuments.enumerated()), id: \.offset) { index, documentURL in
                        HStack(spacing: 12) {
                            Image(systemName: getDocumentIcon(for: documentURL))
                                .font(.system(size: 20, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                                .frame(width: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(documentURL.lastPathComponent)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                    .lineLimit(1)

                                Text(formatFileSize(url: documentURL))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }

                            Spacer()

                            Button {
                                removeDocument(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }
                        }
                        .padding()
                        .background(themeManager.currentTheme.colors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                        )
                    }

                    // Add more button
                    Button {
                        showingDocumentPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(.caption, design: .monospaced))
                            Text("Add More Documents")
                                .font(.system(.body, design: .monospaced))
                        }
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            EntryDocumentPicker(selectedDocuments: $selectedDocuments)
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