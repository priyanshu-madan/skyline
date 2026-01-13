//
//  AddTripView.swift
//  SkyLine
//
//  View for creating new trips
//

import SwiftUI
import CoreLocation
import MapKit

struct AddTripView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss
    
    
    @State private var title = ""
    @State private var destination = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var description = ""
    @State private var selectedDestination: DestinationSuggestion?
    @State private var showingSuggestions = false
    @State private var searchWorkItem: DispatchWorkItem?
    @State private var isSelectingFromDropdown = false
    
    @StateObject private var destinationSearchManager = DestinationSearchManager()
    
    @State private var isCreating = false
    @State private var error: String?
    @State private var showingUploadView = false
    
    // Validation
    private var isValidTrip: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        endDate > startDate
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
                    Text("Create Trip")
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
                        // Trip Title
                        FormField(
                            title: "Trip Title",
                            text: $title,
                            placeholder: "Trip Name"
                        )
                        
                        // Destination with autocomplete and map preview
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    Image(systemName: "mappin")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                        .frame(width: 20, height: 20)
                                        .padding(.leading, 16)

                                    TextField("Destination", text: $destination)
                                        .font(.system(.body, design: .monospaced, weight: .medium))
                                        .padding(.vertical, 16)
                                        .padding(.leading, 12)
                                        .padding(.trailing, 16)
                                        .onChange(of: destination) { _, newValue in
                                            searchDestinations(newValue)
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
                                
                                if showingSuggestions && (!destinationSearchManager.searchResults.isEmpty || destinationSearchManager.isSearching) {
                                    DestinationSearchResultsView(
                                        searchResults: destinationSearchManager.searchResults,
                                        isSearching: destinationSearchManager.isSearching,
                                        onSelect: { completion in
                                            selectDestination(completion)
                                        }
                                    )
                                }
                            }

                            // Map preview for selected destination
                            if let selectedDest = selectedDestination {
                                destinationMapPreview(for: selectedDest)
                            }
                        }
                        
                        // Date Range - Grid layout like Builder.io
                        HStack(spacing: 12) {
                            // Start Date
                            HStack(spacing: 0) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    .frame(width: 20, height: 20)
                                    .padding(.leading, 16)
                                
                                DatePicker("", selection: $startDate, displayedComponents: .date)
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
                            
                            // End Date
                            HStack(spacing: 0) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    .frame(width: 20, height: 20)
                                    .padding(.leading, 16)
                                
                                DatePicker("", selection: $endDate, displayedComponents: .date)
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
                        }
                        
                        // Description
                        FormField(
                            title: "Description",
                            text: $description,
                            placeholder: "Add notes about your trip...",
                            isMultiline: true,
                            icon: "doc.text"
                        )
                    }
                    
                    // Action buttons
                    actionButtonsSection
                        
                        // Error message
                        if let error = error {
                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        }
        .sheet(isPresented: $showingUploadView) {
            UploadItineraryView { parsedItinerary in
                handleImportedItinerary(parsedItinerary)
            }
            .environmentObject(themeManager)
        }
    }

    // MARK: - Destination Map Preview
    private func destinationMapPreview(for destination: DestinationSuggestion) -> some View {
        let coordinate = CLLocationCoordinate2D(
            latitude: destination.latitude,
            longitude: destination.longitude
        )
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
        .disabled(true)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(themeManager.currentTheme.colors.surface.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(themeManager.currentTheme.colors.border.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            
            // Create button
            Button {
                createTrip()
            } label: {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Creating...")
                    } else {
                        Text("Create Trip")
                    }
                }
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isValidTrip ? themeManager.currentTheme.colors.primary : Color.gray)
                )
            }
            .disabled(!isValidTrip || isCreating)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Methods

    private func searchDestinations(_ query: String) {
        // Don't trigger search if we're programmatically setting from dropdown
        if isSelectingFromDropdown {
            isSelectingFromDropdown = false
            return
        }

        // Cancel previous search
        searchWorkItem?.cancel()

        guard !query.isEmpty, query.count > 2 else {
            destinationSearchManager.clearSearch()
            showingSuggestions = false
            return
        }

        // Debounce search requests
        let workItem = DispatchWorkItem {
            destinationSearchManager.search(for: query)
            showingSuggestions = true
        }

        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    private func selectDestination(_ completion: MKLocalSearchCompletion) {
        Task {
            if let destinationSuggestion = await destinationSearchManager.getLocationDetails(for: completion) {
                await MainActor.run {
                    selectedDestination = destinationSuggestion
                    isSelectingFromDropdown = true
                    destination = destinationSuggestion.displayName
                    showingSuggestions = false
                }
            }
        }
    }
    
    private func createTrip() {
        guard isValidTrip else { return }

        isCreating = true
        error = nil

        Task {
            let tripId = UUID().uuidString

            let trip = Trip(
                id: tripId,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                destinationCode: selectedDestination?.airportCode,
                startDate: startDate,
                endDate: endDate,
                description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
                coverImageURL: nil,
                latitude: selectedDestination?.latitude,
                longitude: selectedDestination?.longitude
            )

            let result = await tripStore.addTrip(trip)

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
    
    private func handleImportedItinerary(_ parsedItinerary: ParsedItinerary) {
        // Pre-fill form with imported data
        if let tripTitle = parsedItinerary.metadata.tripTitle {
            title = tripTitle
        }
        
        if let destination = parsedItinerary.metadata.destination {
            self.destination = destination
        }
        
        if let startDate = parsedItinerary.metadata.estimatedStartDate {
            self.startDate = startDate
        }
        
        if let endDate = parsedItinerary.metadata.estimatedEndDate {
            self.endDate = endDate
        }
        
        // Set description to indicate import
        description = "Itinerary imported with \(parsedItinerary.items.count) activities"
        
        // Create the trip with imported data
        createTripFromItinerary(parsedItinerary)
    }
    
    private func createTripFromItinerary(_ parsedItinerary: ParsedItinerary) {
        guard let suggestedTrip = parsedItinerary.suggestTrip() else {
            error = "Unable to create trip from imported data"
            return
        }
        
        isCreating = true
        error = nil
        
        Task {
            let result = await tripStore.addTrip(suggestedTrip)
            
            switch result {
            case .success:
                // Add all itinerary items as trip entries
                let tripEntries = parsedItinerary.toTripEntries(tripId: suggestedTrip.id)
                
                for entry in tripEntries {
                    await tripStore.addEntry(entry)
                }
                
                await MainActor.run {
                    isCreating = false
                    dismiss()
                }
                
            case .failure(let tripError):
                await MainActor.run {
                    isCreating = false
                    error = tripError.localizedDescription
                }
            }
        }
    }
}

// MARK: - Form Field Component
struct FormField: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let title: String
    @Binding var text: String
    let placeholder: String
    var isRequired: Bool = false
    var isMultiline: Bool = false
    var icon: String?
    
    var body: some View {
        if isMultiline {
            // Multiline text field with icon
            HStack(alignment: .top, spacing: 0) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .padding(.leading, 16)
                        .padding(.top, 16)
                }
                
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(3...6)
                    .padding(.vertical, 16)
                    .padding(.leading, icon != nil ? 12 : 16)
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
        } else {
            // Single line text field with icon
            HStack(spacing: 0) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .padding(.leading, 16)
                }
                
                TextField(placeholder, text: $text)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .padding(.vertical, 16)
                    .padding(.leading, icon != nil ? 12 : 16)
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
    }
}

// MARK: - Destination Search Results
struct DestinationSearchResultsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let searchResults: [MKLocalSearchCompletion]
    let isSearching: Bool
    let onSelect: (MKLocalSearchCompletion) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                        .scaleEffect(0.8)
                    
                    Text("Searching destinations...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                .padding()
                .background(themeManager.currentTheme.colors.surface)
            } else {
                ForEach(Array(searchResults.enumerated()), id: \.element.title) { index, result in
                    Button {
                        onSelect(result)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                    .lineLimit(1)
                                
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "location")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                        }
                        .padding()
                        .background(themeManager.currentTheme.colors.surface)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if index < searchResults.count - 1 {
                        Divider()
                            .foregroundColor(themeManager.currentTheme.colors.border)
                    }
                }
            }
        }
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}


#Preview {
    AddTripView()
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}