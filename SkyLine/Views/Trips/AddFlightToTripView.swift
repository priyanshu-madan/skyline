//
//  AddFlightToTripView.swift
//  SkyLine
//
//  View for adding flights to existing trips or creating new trips
//

import SwiftUI

struct AddFlightToTripView: View {
    let flight: Flight
    
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @StateObject private var flightTripService = FlightTripService.shared
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedOption: AddFlightOption = .existingTrip
    @State private var selectedTripId: String?
    @State private var relevantTrips: [Trip] = []
    
    // New trip fields
    @State private var newTripTitle = ""
    @State private var newTripStartDate = Date()
    @State private var newTripEndDate = Date()
    
    // State management
    @State private var isProcessing = false
    @State private var showingSuccess = false
    @State private var error: String?
    
    enum AddFlightOption {
        case existingTrip
        case newTrip
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                themeManager.currentTheme.colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Flight Preview Card
                        flightPreviewCard
                        
                        // Options Picker
                        optionsPicker
                        
                        // Content based on selected option
                        if selectedOption == .existingTrip {
                            existingTripsSection
                        } else {
                            newTripSection
                        }
                        
                        // Action Button
                        actionButton
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Add Flight to Trip")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
            .onAppear {
                setupInitialState()
            }
            .alert("Success!", isPresented: $showingSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Flight has been added to your trip successfully!")
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") {
                    error = nil
                }
            } message: {
                Text(error ?? "")
            }
        }
    }
    
    // MARK: - Flight Preview Card
    
    private var flightPreviewCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FLIGHT")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.flightNumber)
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                }
                
                Spacer()
                
                if let airline = flight.airline {
                    Text(airline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
            }
            
            HStack {
                // Departure
                VStack(alignment: .leading, spacing: 4) {
                    Text(flight.departure.code)
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text(flight.departure.city)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.departure.displayTime)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                }
                
                Spacer()
                
                // Arrow and duration
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    if let duration = flight.flightDuration {
                        Text(duration)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }
                
                Spacer()
                
                // Arrival
                VStack(alignment: .trailing, spacing: 4) {
                    Text(flight.arrival.code)
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text(flight.arrival.city)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(flight.arrival.displayTime)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.currentTheme.colors.surface)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Options Picker
    
    private var optionsPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { selectedOption = .existingTrip }) {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(selectedOption == .existingTrip ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                        
                        Text("Add to Existing Trip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedOption == .existingTrip ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedOption == .existingTrip ? themeManager.currentTheme.colors.primary.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { selectedOption = .newTrip }) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(selectedOption == .newTrip ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                        
                        Text("Create New Trip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedOption == .newTrip ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedOption == .newTrip ? themeManager.currentTheme.colors.primary.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.currentTheme.colors.surface)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Existing Trips Section
    
    private var existingTripsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Select Trip")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Spacer()
                
                if relevantTrips.isEmpty {
                    Text("No relevant trips found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
            }
            
            if relevantTrips.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text("No matching trips found")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text("Try creating a new trip instead")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(relevantTrips) { trip in
                        tripSelectionCard(trip)
                    }
                }
            }
        }
    }
    
    private func tripSelectionCard(_ trip: Trip) -> some View {
        Button(action: { selectedTripId = trip.id }) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(trip.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                        .multilineTextAlignment(.leading)
                    
                    Text(trip.destination)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(trip.dateRangeText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: trip.isActive ? "location" : trip.isUpcoming ? "calendar" : "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(trip.statusColor))
                        
                        Text(trip.statusText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(trip.statusColor))
                    }
                }
                
                Spacer()
                
                if selectedTripId == trip.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedTripId == trip.id ? themeManager.currentTheme.colors.primary.opacity(0.1) : themeManager.currentTheme.colors.surface)
                    .stroke(selectedTripId == trip.id ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.border, lineWidth: selectedTripId == trip.id ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - New Trip Section
    
    private var newTripSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create New Trip")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trip Title")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    TextField("Enter trip title", text: $newTripTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Date")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        DatePicker("Start Date", selection: $newTripStartDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(CompactDatePickerStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("End Date")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        
                        DatePicker("End Date", selection: $newTripEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(CompactDatePickerStyle())
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.currentTheme.colors.surface)
                    .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        Button(action: processAddFlight) {
            HStack {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: selectedOption == .existingTrip ? "folder.badge.plus" : "plus.circle")
                        .font(.system(size: 18, weight: .medium))
                }
                
                Text(isProcessing ? "Adding Flight..." : 
                     selectedOption == .existingTrip ? "Add to Trip" : "Create Trip with Flight")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isActionButtonEnabled ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
            )
        }
        .disabled(!isActionButtonEnabled || isProcessing)
        .buttonStyle(PlainButtonStyle())
    }
    
    private var isActionButtonEnabled: Bool {
        if selectedOption == .existingTrip {
            return selectedTripId != nil
        } else {
            return !newTripTitle.isEmpty
        }
    }
    
    // MARK: - Helper Functions
    
    private func setupInitialState() {
        // Find relevant trips for this flight
        relevantTrips = flightTripService.findRelevantTrips(for: flight)
        
        // Set up new trip defaults
        let suggestedTrip = flightTripService.createTripFromFlight(flight)
        newTripTitle = suggestedTrip.title
        newTripStartDate = suggestedTrip.startDate
        newTripEndDate = suggestedTrip.endDate
        
        // If we have relevant trips, default to existing trip option
        if !relevantTrips.isEmpty {
            selectedOption = .existingTrip
            selectedTripId = relevantTrips.first?.id
        } else {
            selectedOption = .newTrip
        }
    }
    
    private func processAddFlight() {
        isProcessing = true
        error = nil
        
        Task {
            do {
                if selectedOption == .existingTrip {
                    guard let tripId = selectedTripId else {
                        await MainActor.run {
                            error = "Please select a trip"
                            isProcessing = false
                        }
                        return
                    }
                    
                    let result = await flightTripService.addFlightToTrip(flight, tripId: tripId)
                    await MainActor.run {
                        switch result {
                        case .success:
                            showingSuccess = true
                        case .failure(let error):
                            self.error = error.localizedDescription
                        }
                        isProcessing = false
                    }
                } else {
                    let result = await flightTripService.createTripWithFlight(
                        flight,
                        customTitle: newTripTitle,
                        customStartDate: newTripStartDate,
                        customEndDate: newTripEndDate
                    )
                    
                    await MainActor.run {
                        switch result {
                        case .success:
                            showingSuccess = true
                        case .failure(let error):
                            self.error = error.localizedDescription
                        }
                        isProcessing = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview
struct AddFlightToTripView_Previews: PreviewProvider {
    static var previews: some View {
        AddFlightToTripView(flight: Flight.sample)
            .environmentObject(ThemeManager())
            .environmentObject(TripStore.shared)
    }
}