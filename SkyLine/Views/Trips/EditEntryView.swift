//
//  EditEntryView.swift
//  SkyLine
//
//  View for editing existing trip entries
//

import SwiftUI
import CoreLocation

struct EditEntryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss
    
    let entry: TripEntry
    
    @State private var selectedEntryType: TripEntryType
    @State private var title: String
    @State private var content: String
    @State private var timestamp: Date
    @State private var useCurrentLocation: Bool
    @State private var currentLocation: CLLocation?
    @State private var locationName: String
    
    @State private var isUpdating = false
    @State private var error: String?
    @State private var showingLocationPicker = false
    @State private var showingDeleteConfirmation = false
    
    @StateObject private var locationManager = SkyLineLocationManager()
    
    init(entry: TripEntry) {
        self.entry = entry
        self._selectedEntryType = State(initialValue: entry.entryType)
        self._title = State(initialValue: entry.title)
        self._content = State(initialValue: entry.content)
        self._timestamp = State(initialValue: entry.timestamp)
        self._useCurrentLocation = State(initialValue: entry.hasLocation)
        self._locationName = State(initialValue: entry.locationName ?? "")
        
        if let lat = entry.latitude, let lng = entry.longitude {
            self._currentLocation = State(initialValue: CLLocation(latitude: lat, longitude: lng))
        }
    }
    
    private var isValidEntry: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Edit Entry")
                            .font(.system(.largeTitle, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Text("Update this moment")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    .padding(.top, 20)
                    
                    // Entry type picker
                    entryTypePicker
                    
                    // Entry details form
                    entryDetailsForm
                    
                    
                    // Timestamp section
                    timestampSection
                    
                    // Location section
                    locationSection
                    
                    // Action buttons
                    actionButtons
                    
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
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
            .onAppear {
                requestLocationIfNeeded()
            }
        }
        .confirmationDialog("Delete Entry", isPresented: $showingDeleteConfirmation) {
            Button("Delete Entry", role: .destructive) {
                deleteEntry()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this entry? This action cannot be undone.")
        }
    }
    
    // MARK: - Entry Type Picker
    
    private var entryTypePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entry Type")
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(TripEntryType.allCases, id: \.self) { type in
                    entryTypeCard(for: type)
                }
            }
        }
    }
    
    private func entryTypeCard(for type: TripEntryType) -> some View {
        Button {
            selectedEntryType = type
        } label: {
            VStack(spacing: 8) {
                Text(type.emoji)
                    .font(.system(size: 24))
                
                Text(type.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(selectedEntryType == type ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedEntryType == type ? themeManager.currentTheme.colors.primary.opacity(0.1) : themeManager.currentTheme.colors.surface)
                    .stroke(selectedEntryType == type ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.border, lineWidth: selectedEntryType == type ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Entry Details Form
    
    private var entryDetailsForm: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                TextField("What happened?", text: $title)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(themeManager.currentTheme.colors.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                TextField("Tell the story...", text: $content, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(4...8)
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
    
    
    // MARK: - Timestamp Section
    
    private var timestampSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When")
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            DatePicker("Timestamp", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
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
    
    // MARK: - Location Section
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where")
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            VStack(spacing: 12) {
                Toggle("Use current location", isOn: $useCurrentLocation)
                    .font(.system(.body, design: .monospaced))
                    .tint(themeManager.currentTheme.colors.primary)
                
                if !useCurrentLocation {
                    TextField("Location name", text: $locationName)
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
            .padding()
            .background(themeManager.currentTheme.colors.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
            )
        }
        .onChange(of: useCurrentLocation) { _, newValue in
            if newValue {
                requestLocationIfNeeded()
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Update button
            Button {
                updateEntry()
            } label: {
                HStack {
                    if isUpdating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Updating...")
                    } else {
                        Image(systemName: "checkmark")
                        Text("Update Entry")
                    }
                }
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isValidEntry ? themeManager.currentTheme.colors.primary : Color.gray)
                .cornerRadius(8)
            }
            .disabled(!isValidEntry || isUpdating)
        }
    }
    
    // MARK: - Helper Functions
    
    private func requestLocationIfNeeded() {
        if useCurrentLocation {
            locationManager.requestLocation()
            currentLocation = locationManager.currentLocation
        }
    }
    
    
    private func updateEntry() {
        isUpdating = true
        error = nil
        
        let updatedEntry = TripEntry(
            id: entry.id,
            tripId: entry.tripId,
            timestamp: timestamp,
            entryType: selectedEntryType,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURLs: entry.imageURLs, // Keep existing images for now
            latitude: useCurrentLocation ? currentLocation?.coordinate.latitude : nil,
            longitude: useCurrentLocation ? currentLocation?.coordinate.longitude : nil,
            locationName: useCurrentLocation ? (currentLocation != nil ? "Current Location" : nil) : (locationName.isEmpty ? nil : locationName),
            createdAt: entry.createdAt,
            updatedAt: Date()
        )
        
        Task {
            let result = await tripStore.updateEntry(updatedEntry)
            
            await MainActor.run {
                isUpdating = false
                
                switch result {
                case .success:
                    dismiss()
                case .failure(let tripError):
                    error = tripError.localizedDescription
                }
            }
        }
    }
    
    private func deleteEntry() {
        Task {
            let result = await tripStore.deleteEntry(entry.id, tripId: entry.tripId)
            
            await MainActor.run {
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    EditEntryView(entry: TripEntry.sample)
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}