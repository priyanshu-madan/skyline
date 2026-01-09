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
    
    @StateObject private var destinationSearchManager = DestinationSearchManager()
    
    @State private var isCreating = false
    @State private var error: String?
    @State private var showingUploadView = false
    @State private var showingLocationPicker = false
    
    // Validation
    private var isValidTrip: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        endDate > startDate
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("New Trip")
                            .font(.system(.largeTitle, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        Text("Document your next adventure")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    .padding(.top, 20)
                    
                    
                    // Form fields
                    VStack(spacing: 20) {
                        // Trip Title
                        FormField(
                            title: "Trip Title",
                            text: $title,
                            placeholder: "Summer in Tokyo",
                            isRequired: true
                        )
                        
                        // Destination with autocomplete
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Destination")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    .textCase(.uppercase)
                                
                                Text("*")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.red)
                                
                                Spacer()
                                
                                Button {
                                    showingLocationPicker = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "map")
                                        Text("Map")
                                    }
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                                }
                            }
                            
                            VStack(spacing: 0) {
                                TextField("Tokyo, Japan", text: $destination)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                                    .background(themeManager.currentTheme.colors.surface)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                                    )
                                    .onChange(of: destination) { _, newValue in
                                        searchDestinations(newValue)
                                    }
                                
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
                        }
                        
                        // Date Range
                        VStack(spacing: 16) {
                            HStack {
                                Text("Travel Dates")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    .textCase(.uppercase)
                                
                                Spacer()
                            }
                            
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Start Date")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    
                                    DatePicker("", selection: $startDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .font(.system(.body, design: .monospaced))
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("End Date")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    
                                    DatePicker("", selection: $endDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                        
                        // Description
                        FormField(
                            title: "Description",
                            text: $description,
                            placeholder: "What makes this trip special?",
                            isMultiline: true
                        )
                    }
                    
                    // Create button
                    Button {
                        createTrip()
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Creating...")
                            } else {
                                Image(systemName: "plus")
                                Text("Create Trip")
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isValidTrip ? themeManager.currentTheme.colors.primary : Color.gray)
                        .cornerRadius(8)
                    }
                    .disabled(!isValidTrip || isCreating)
                    
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
        .sheet(isPresented: $showingUploadView) {
            UploadItineraryView { parsedItinerary in
                handleImportedItinerary(parsedItinerary)
            }
            .environmentObject(themeManager)
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView { selectedDestination in
                handleLocationSelection(selectedDestination)
            }
            .environmentObject(themeManager)
        }
    }
    
    
    private func searchDestinations(_ query: String) {
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
                    destination = destinationSuggestion.displayName
                    showingSuggestions = false
                }
            }
        }
    }
    
    private func handleLocationSelection(_ destinationSuggestion: DestinationSuggestion) {
        selectedDestination = destinationSuggestion
        destination = destinationSuggestion.displayName
        showingLocationPicker = false
    }
    
    private func createTrip() {
        guard isValidTrip else { return }
        
        isCreating = true
        error = nil
        
        let trip = Trip(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationCode: selectedDestination?.airportCode,
            startDate: startDate,
            endDate: endDate,
            description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: selectedDestination?.latitude,
            longitude: selectedDestination?.longitude
        )
        
        Task {
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .textCase(.uppercase)
                
                if isRequired {
                    Text("*")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
            
            if isMultiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3...6)
                    .padding()
                    .background(themeManager.currentTheme.colors.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                    )
            } else {
                TextField(placeholder, text: $text)
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
        .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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