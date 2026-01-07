//
//  TripDetailView.swift
//  SkyLine
//
//  Detailed trip view with vertical timeline
//

import SwiftUI

enum PresentedSheet: Identifiable {
    case addEntry
    case editEntry(TripEntry)
    case uploadItinerary
    case addEntryMenu
    
    var id: String {
        switch self {
        case .addEntry:
            return "addEntry"
        case .editEntry(let entry):
            return "editEntry_\(entry.id)"
        case .uploadItinerary:
            return "uploadItinerary"
        case .addEntryMenu:
            return "addEntryMenu"
        }
    }
}

struct TripDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @EnvironmentObject var flightStore: FlightStore
    @Environment(\.dismiss) private var dismiss
    
    let trip: Trip
    let onFlightSelected: ((Flight, Trip) -> Void)?
    @State private var presentedSheet: PresentedSheet?
    @State private var refreshID = UUID()
    
    init(trip: Trip, onFlightSelected: ((Flight, Trip) -> Void)? = nil) {
        self.trip = trip
        self.onFlightSelected = onFlightSelected
    }
    
    private var entries: [TripEntry] {
        tripStore.getEntries(for: trip.id).sortedByTimestamp()
    }
    
    private var groupedEntries: [(Date, [TripEntry])] {
        tripStore.getEntriesGroupedByDay(for: trip.id)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        // Trip header
                        TripHeaderView(trip: trip)
                        
                        // Timeline content
                        if entries.isEmpty {
                            EmptyTimelineView(onAddEntry: { presentedSheet = .addEntryMenu })
                        } else {
                            TimelineView(
                                groupedEntries: groupedEntries,
                                onEntryTap: { entry in
                                    handleEntryTap(entry)
                                },
                                onEntryLongPress: { entry in
                                    handleEntryLongPress(entry)
                                }
                            )
                        }
                    }
                }
                
                // Floating add button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        Button {
                            presentedSheet = .addEntryMenu
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(themeManager.currentTheme.colors.primary)
                                .clipShape(Circle())
                                .shadow(
                                    color: themeManager.currentTheme.colors.primary.opacity(0.3),
                                    radius: 8,
                                    x: 0,
                                    y: 4
                                )
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            // Edit trip
                        } label: {
                            Label("Edit Trip", systemImage: "pencil")
                        }
                        
                        Button {
                            // Share trip
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            // Delete trip
                        } label: {
                            Label("Delete Trip", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addEntry:
                AddEntryView(tripId: trip.id)
                    .environmentObject(themeManager)
                    .environmentObject(tripStore)
            case .editEntry(let entry):
                EditEntryView(entry: entry)
                    .environmentObject(themeManager)
                    .environmentObject(tripStore)
            case .uploadItinerary:
                UploadItineraryView { parsedItinerary in
                    handleProcessedItinerary(parsedItinerary)
                }
                .environmentObject(themeManager)
            case .addEntryMenu:
                AddEntryMenuView(trip: trip) { option in
                    presentedSheet = nil
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        switch option {
                        case .manual:
                            presentedSheet = .addEntry
                        case .importFiles:
                            presentedSheet = .uploadItinerary
                        case .askAI:
                            // Future implementation
                            break
                        }
                    }
                }
                .environmentObject(themeManager)
            }
        }
        .id(refreshID)
        .onAppear {
            Task {
                await tripStore.fetchEntriesForTrip(trip.id)
                await migrateFlightEntries()
                refreshID = UUID()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleProcessedItinerary(_ parsedItinerary: ParsedItinerary) {
        Task {
            do {
                // Convert all items to trip entries for this specific trip
                let tripEntries = parsedItinerary.toTripEntries(tripId: trip.id)
                
                // Add each entry to the trip
                for entry in tripEntries {
                    let result = await tripStore.addEntry(entry)
                    if case .failure(let error) = result {
                        print("Failed to add entry: \(error.localizedDescription)")
                        return
                    }
                }
                
                await MainActor.run {
                    presentedSheet = nil
                    refreshID = UUID()
                }
                
            } catch {
                print("Failed to add entries: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleEntryTap(_ entry: TripEntry) {
        // Only handle flight entries for tap - show flight details
        if entry.entryType == .flight {
            if let flightId = entry.flightId {
                // Find the flight in the flight store and navigate to details
                if let flight = flightStore.flights.first(where: { $0.id == flightId }) {
                    // Dismiss the trip view and navigate to flight details in main UI
                    dismiss()
                    onFlightSelected?(flight, trip)
                }
            }
        }
        // For non-flight entries, do nothing on tap
    }
    
    private func handleEntryLongPress(_ entry: TripEntry) {
        // Long press always shows edit view for any entry type
        presentedSheet = .editEntry(entry)
    }
    
    /// Migrates existing flight entries that are missing flightId
    private func migrateFlightEntries() async {
        let flightEntries = tripStore.getEntries(for: trip.id).filter { 
            $0.entryType == .flight && $0.flightId == nil 
        }
        
        // Only migrate if there are entries that need migration
        guard !flightEntries.isEmpty else { return }
        
        for entry in flightEntries {
            // Try to find a matching flight based on the title
            if let matchedFlight = findFlightForEntry(entry) {
                // Create updated entry with flightId
                let updatedEntry = TripEntry(
                    id: entry.id,
                    tripId: entry.tripId,
                    timestamp: entry.timestamp,
                    entryType: entry.entryType,
                    title: entry.title,
                    content: entry.content,
                    imageURLs: entry.imageURLs,
                    latitude: entry.latitude,
                    longitude: entry.longitude,
                    locationName: entry.locationName,
                    flightId: matchedFlight.id,
                    createdAt: entry.createdAt,
                    updatedAt: Date()
                )
                
                // Update the entry
                await tripStore.updateEntry(updatedEntry)
            }
        }
    }
    
    /// Try to find a matching flight for an entry based on title and content
    private func findFlightForEntry(_ entry: TripEntry) -> Flight? {
        // Extract flight number from title (e.g., "Flight AA4335 - JFK to CVG")
        let title = entry.title
        let components = title.components(separatedBy: " ")
        
        for i in 0..<components.count {
            if components[i] == "Flight" && i + 1 < components.count {
                let flightNumber = components[i + 1]
                
                // Look for flight with matching flight number
                if let flight = flightStore.flights.first(where: { $0.flightNumber == flightNumber }) {
                    return flight
                }
            }
        }
        
        // If no exact match, try to match by airport codes in title
        for flight in flightStore.flights {
            if title.contains(flight.departure.code) && title.contains(flight.arrival.code) {
                return flight
            }
        }
        
        return nil
    }
}

// MARK: - Trip Header
struct TripHeaderView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let trip: Trip
    
    var body: some View {
        VStack(spacing: 16) {
            // Trip image
            TripHeaderImageView(trip: trip)
                .frame(height: 200)
                .clipped()
            
            // Trip info
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(trip.title)
                        .font(.system(.largeTitle, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                        .multilineTextAlignment(.center)
                    
                    Text(trip.destination)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("Duration")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        
                        Text(trip.durationText)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                    
                    VStack(spacing: 4) {
                        Text("Status")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            
                            Text(trip.statusText)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(themeManager.currentTheme.colors.text)
                        }
                    }
                    
                    VStack(spacing: 4) {
                        Text("Dates")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        
                        Text(trip.dateRangeText)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                }
                
                if let description = trip.description, !description.isEmpty {
                    Text(description)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(themeManager.currentTheme.colors.background)
    }
    
    private var statusColor: Color {
        switch trip.statusColor {
        case "green":
            return .green
        case "blue":
            return .blue
        default:
            return .gray
        }
    }
}

// MARK: - Trip Header Image
struct TripHeaderImageView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let trip: Trip
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: themeManager.currentTheme == .dark ? [
                    Color(red: 0.31, green: 0.31, blue: 0.31),
                    Color(red: 0.11, green: 0.11, blue: 0.15)
                ] : [
                    Color(red: 0.98, green: 0.98, blue: 0.98),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Destination image if available
            if let coverImageURL = trip.coverImageURL,
               let url = URL(string: coverImageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                        .scaleEffect(0.8)
                }
            } else {
                // Fallback with destination name
                VStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .font(.system(size: 48, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(trip.destination)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
            }
        }
    }
}

// MARK: - Timeline View
struct TimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let groupedEntries: [(Date, [TripEntry])]
    let onEntryTap: (TripEntry) -> Void
    let onEntryLongPress: (TripEntry) -> Void
    
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(groupedEntries.enumerated()), id: \.offset) { dayIndex, dayGroup in
                let (date, entries) = dayGroup
                
                // Day header
                TimelineDayHeader(date: date, entryCount: entries.count)
                    .padding(.horizontal, 20)
                    .padding(.top, dayIndex == 0 ? 20 : 32)
                    .padding(.bottom, 16)
                
                // Entries for this day
                ForEach(Array(entries.enumerated()), id: \.element.id) { entryIndex, entry in
                    TimelineEntryView(
                        entry: entry,
                        isLast: entryIndex == entries.count - 1 && dayIndex == groupedEntries.count - 1,
                        onTap: { onEntryTap(entry) },
                        onLongPress: { onEntryLongPress(entry) }
                    )
                    .padding(.horizontal, 20)
                }
            }
            
            // Bottom padding
            Color.clear
                .frame(height: 100)
        }
    }
}

// MARK: - Timeline Day Header
struct TimelineDayHeader: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let date: Date
    let entryCount: Int
    
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("\(entryCount) \(entryCount == 1 ? "entry" : "entries")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Timeline Entry View
struct TimelineEntryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let entry: TripEntry
    let isLast: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline line and dot
            VStack(spacing: 0) {
                // Dot
                ZStack {
                    Circle()
                        .fill(themeManager.currentTheme.colors.background)
                        .frame(width: 16, height: 16)
                    
                    Circle()
                        .fill(entryTypeColor)
                        .frame(width: 12, height: 12)
                }
                
                // Vertical line (if not last)
                if !isLast {
                    Rectangle()
                        .fill(themeManager.currentTheme.colors.border)
                        .frame(width: 2)
                        .frame(minHeight: 60)
                }
            }
            .frame(width: 16)
            
            // Entry content
            TimelineEntryCard(entry: entry, onTap: onTap, onLongPress: onLongPress)
                .padding(.bottom, isLast ? 0 : 16)
        }
    }
    
    private var entryTypeColor: Color {
        switch entry.entryType.color {
        case "orange":
            return .orange
        case "purple":
            return .purple
        case "blue":
            return .blue
        case "green":
            return .green
        case "red":
            return .red
        case "pink":
            return .pink
        case "yellow":
            return .yellow
        default:
            return .gray
        }
    }
}

// MARK: - Timeline Entry Card
struct TimelineEntryCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let entry: TripEntry
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with type and time
            HStack {
                HStack(spacing: 6) {
                    Text(entry.entryType.emoji)
                        .font(.system(.body, design: .monospaced))
                    
                    Text(entry.entryType.displayName)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                }
                
                Spacer()
                
                Text(entry.timeText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            // Title and content
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(3)
                }
            }
            
            // Location if available
            if !entry.displayLocation.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(entry.displayLocation)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                }
            }
            
            // Images if available
            if entry.hasImages {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entry.imageURLs.prefix(3), id: \.self) { imageURL in
                            if let url = URL(string: imageURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        .clipped()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(themeManager.currentTheme.colors.surface)
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        )
                                }
                            }
                        }
                        
                        if entry.imageURLs.count > 3 {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(themeManager.currentTheme.colors.surface)
                                    .frame(width: 60, height: 60)
                                
                                Text("+\(entry.imageURLs.count - 3)")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(16)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
}

// MARK: - Empty Timeline
struct EmptyTimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let onAddEntry: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 48, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                
                Text("Start Your Timeline")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("Add your first entry to document this amazing trip")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                onAddEntry()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add First Entry")
                }
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 40)
    }
}

// MARK: - Placeholder Views

struct EntryDetailView: View {
    let entry: TripEntry
    
    var body: some View {
        Text("Entry Detail View - \(entry.title)")
            .font(.system(.title, design: .monospaced))
    }
}

// MARK: - Add Entry Menu View

enum AddEntryOption {
    case manual
    case importFiles
    case askAI
    
    var title: String {
        switch self {
        case .manual: return "Manual Entry"
        case .importFiles: return "Import from Files"
        case .askAI: return "Ask AI to Plan"
        }
    }
    
    var subtitle: String {
        switch self {
        case .manual: return "Add activities manually"
        case .importFiles: return "Upload images or documents"
        case .askAI: return "Let AI create your itinerary"
        }
    }
    
    var icon: String {
        switch self {
        case .manual: return "pencil"
        case .importFiles: return "doc.text.magnifyingglass"
        case .askAI: return "wand.and.stars"
        }
    }
    
    var isEnabled: Bool {
        switch self {
        case .manual, .importFiles: return true
        case .askAI: return false // Future implementation
        }
    }
}

struct AddEntryMenuView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    let trip: Trip
    let onSelection: (AddEntryOption) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                    
                    Text("Add to Trip")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text("Choose how you'd like to add activities to \"\(trip.title)\"")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Options
                VStack(spacing: 16) {
                    ForEach([AddEntryOption.manual, .importFiles, .askAI], id: \.title) { option in
                        AddEntryOptionButton(
                            option: option,
                            onTap: {
                                if option.isEnabled {
                                    onSelection(option)
                                }
                            }
                        )
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddEntryOptionButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let option: AddEntryOption
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: option.icon)
                    .font(.system(size: 24))
                    .foregroundColor(option.isEnabled ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(option.title)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundColor(option.isEnabled ? themeManager.currentTheme.colors.text : themeManager.currentTheme.colors.textSecondary)
                        
                        if !option.isEnabled {
                            Text("Coming Soon")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(themeManager.currentTheme.colors.primary)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(option.subtitle)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if option.isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
            }
            .padding()
            .background(option.isEnabled ? themeManager.currentTheme.colors.surface : themeManager.currentTheme.colors.surface.opacity(0.5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(option.isEnabled ? themeManager.currentTheme.colors.border : themeManager.currentTheme.colors.border.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!option.isEnabled)
    }
}

#Preview {
    TripDetailView(trip: Trip.sample)
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}