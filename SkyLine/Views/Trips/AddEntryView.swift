//
//  AddEntryView.swift
//  SkyLine
//
//  View for adding new timeline entries to trips
//

import SwiftUI
import PhotosUI
import CoreLocation

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
    @State private var timestamp = Date()
    @State private var useCurrentLocation = true
    @State private var currentLocation: CLLocation?
    @State private var locationName = ""
    
    @State private var isCreating = false
    @State private var error: String?
    @State private var showingLocationPicker = false
    
    @StateObject private var locationManager = SkyLineLocationManager()
    
    private var isValidEntry: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("New Entry")
                            .font(.system(.largeTitle, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Text("Capture this moment")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    .padding(.top, 20)
                    
                    // Entry Type Selection
                    EntryTypeSelector(selectedType: $selectedEntryType)
                    
                    // Photos Section
                    PhotosSection(
                        selectedPhotos: $selectedPhotos,
                        selectedImages: $selectedImages
                    )
                    
                    // Entry Details
                    VStack(spacing: 20) {
                        // Title
                        FormField(
                            title: "Title",
                            text: $title,
                            placeholder: getPlaceholderTitle(),
                            isRequired: true
                        )
                        
                        // Content/Description
                        FormField(
                            title: "What happened?",
                            text: $content,
                            placeholder: getPlaceholderContent(),
                            isMultiline: true
                        )
                        
                        // Timestamp
                        VStack(alignment: .leading, spacing: 8) {
                            Text("When")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                .textCase(.uppercase)
                            
                            DatePicker("", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        // Location Section
                        LocationSection(
                            useCurrentLocation: $useCurrentLocation,
                            currentLocation: $currentLocation,
                            locationName: $locationName,
                            showingLocationPicker: $showingLocationPicker
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
        .onAppear {
            requestLocationIfNeeded()
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
    
    private func requestLocationIfNeeded() {
        if useCurrentLocation {
            locationManager.requestLocation()
            currentLocation = locationManager.currentLocation
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
                latitude: useCurrentLocation ? currentLocation?.coordinate.latitude : nil,
                longitude: useCurrentLocation ? currentLocation?.coordinate.longitude : nil,
                locationName: locationName.isEmpty ? nil : locationName.trimmingCharacters(in: .whitespacesAndNewlines)
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

// MARK: - Entry Type Selector
struct EntryTypeSelector: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedType: TripEntryType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What kind of entry?")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .textCase(.uppercase)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(TripEntryType.allCases, id: \.self) { entryType in
                    EntryTypeButton(
                        entryType: entryType,
                        isSelected: selectedType == entryType
                    ) {
                        selectedType = entryType
                    }
                }
            }
        }
    }
}

struct EntryTypeButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let entryType: TripEntryType
    let isSelected: Bool
    let onTap: () -> Void
    
    private var typeColor: Color {
        switch entryType.color {
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
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isSelected ? typeColor : themeManager.currentTheme.colors.surface)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? typeColor : themeManager.currentTheme.colors.border, lineWidth: 2)
                    )
                
                Text(entryType.emoji)
                    .font(.system(size: 20, design: .monospaced))
            }
            
            Text(entryType.displayName)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(isSelected ? typeColor : themeManager.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .onTapGesture {
            onTap()
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
            Text("Photos")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .textCase(.uppercase)
            
            if selectedImages.isEmpty {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.currentTheme.colors.surface)
                            .frame(height: 120)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 24, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    
                                    Text("Add Photos")
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                            )
                    }
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

// MARK: - Location Section
struct LocationSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var useCurrentLocation: Bool
    @Binding var currentLocation: CLLocation?
    @Binding var locationName: String
    @Binding var showingLocationPicker: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .textCase(.uppercase)
            
            VStack(spacing: 12) {
                // Current location toggle
                HStack {
                    Toggle("Use current location", isOn: $useCurrentLocation)
                        .font(.system(.body, design: .monospaced))
                        .toggleStyle(SwitchToggleStyle(tint: themeManager.currentTheme.colors.primary))
                    
                    Spacer()
                }
                
                if let location = currentLocation, useCurrentLocation {
                    HStack {
                        Image(systemName: "location.fill")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.primary)
                        
                        Text("\(location.coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), \(location.coordinate.longitude.formatted(.number.precision(.fractionLength(4))))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }
                
                // Manual location name
                if !useCurrentLocation || currentLocation != nil {
                    TextField("Add location name (optional)", text: $locationName)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(themeManager.currentTheme.colors.surface)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                        )
                }
            }
        }
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocation() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

#Preview {
    AddEntryView(tripId: "sample-trip")
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}