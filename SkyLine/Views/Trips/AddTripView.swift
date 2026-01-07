//
//  AddTripView.swift
//  SkyLine
//
//  View for creating new trips
//

import SwiftUI
import CoreLocation

struct AddTripView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss
    
    // Note: DestinationSearchService integration pending - using mock data for now
    
    @State private var title = ""
    @State private var destination = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var description = ""
    @State private var destinationSuggestions: [DestinationSuggestion] = []
    @State private var selectedDestination: DestinationSuggestion?
    @State private var showingSuggestions = false
    
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
                                
                                if showingSuggestions && !destinationSuggestions.isEmpty {
                                    DestinationSuggestionsView(
                                        suggestions: destinationSuggestions,
                                        isSearching: false,
                                        onSelect: { suggestion in
                                            selectedDestination = suggestion
                                            destination = suggestion.displayName
                                            showingSuggestions = false
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
    }
    
    
    private func searchDestinations(_ query: String) {
        guard !query.isEmpty, query.count > 2 else {
            destinationSuggestions = []
            showingSuggestions = false
            return
        }
        
        // Use mock destinations for now until DestinationSearchService is properly integrated
        let suggestions = mockDestinations.filter { destination in
            destination.city.localizedCaseInsensitiveContains(query) ||
            destination.country.localizedCaseInsensitiveContains(query)
        }
        
        destinationSuggestions = Array(suggestions.prefix(5))
        showingSuggestions = true
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

// MARK: - Destination Suggestions
struct DestinationSuggestionsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let suggestions: [DestinationSuggestion]
    let isSearching: Bool
    let onSelect: (DestinationSuggestion) -> Void
    
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
                ForEach(suggestions) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.displayName)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                    .lineLimit(1)
                                
                                if !suggestion.detailText.isEmpty {
                                    Text(suggestion.detailText)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            if let airportCode = suggestion.airportCode {
                                Text(airportCode)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(themeManager.currentTheme.colors.primary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding()
                        .background(themeManager.currentTheme.colors.surface)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if suggestion.id != suggestions.last?.id {
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

// MARK: - Mock Data (Temporary until DestinationSearchService is integrated)
private let mockDestinations: [DestinationSuggestion] = [
    DestinationSuggestion(city: "Tokyo", country: "Japan", airportCode: "NRT", latitude: 35.6762, longitude: 139.6503),
    DestinationSuggestion(city: "Paris", country: "France", airportCode: "CDG", latitude: 48.8566, longitude: 2.3522),
    DestinationSuggestion(city: "London", country: "United Kingdom", airportCode: "LHR", latitude: 51.5074, longitude: -0.1278),
    DestinationSuggestion(city: "New York", country: "United States", airportCode: "JFK", latitude: 40.7128, longitude: -74.0060),
    DestinationSuggestion(city: "Los Angeles", country: "United States", airportCode: "LAX", latitude: 34.0522, longitude: -118.2437),
    DestinationSuggestion(city: "San Francisco", country: "United States", airportCode: "SFO", latitude: 37.7749, longitude: -122.4194),
    DestinationSuggestion(city: "Sydney", country: "Australia", airportCode: "SYD", latitude: -33.8688, longitude: 151.2093),
    DestinationSuggestion(city: "Dubai", country: "United Arab Emirates", airportCode: "DXB", latitude: 25.2048, longitude: 55.2708),
    DestinationSuggestion(city: "Singapore", country: "Singapore", airportCode: "SIN", latitude: 1.3521, longitude: 103.8198),
    DestinationSuggestion(city: "Rome", country: "Italy", airportCode: "FCO", latitude: 41.9028, longitude: 12.4964),
    DestinationSuggestion(city: "Barcelona", country: "Spain", airportCode: "BCN", latitude: 41.3851, longitude: 2.1734),
    DestinationSuggestion(city: "Amsterdam", country: "Netherlands", airportCode: "AMS", latitude: 52.3676, longitude: 4.9041),
    DestinationSuggestion(city: "Bangkok", country: "Thailand", airportCode: "BKK", latitude: 13.7563, longitude: 100.5018),
    DestinationSuggestion(city: "Seoul", country: "South Korea", airportCode: "ICN", latitude: 37.5665, longitude: 126.9780),
    DestinationSuggestion(city: "Hong Kong", country: "Hong Kong", airportCode: "HKG", latitude: 22.3193, longitude: 114.1694)
]

#Preview {
    AddTripView()
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}