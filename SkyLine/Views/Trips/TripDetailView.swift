//
//  TripDetailView.swift
//  SkyLine
//
//  Detailed trip view with vertical timeline
//

import SwiftUI
import MapKit

enum PresentedSheet: Identifiable {
    case addEntry
    case editEntry(TripEntry)
    case uploadItinerary
    case addEntryMenu
    case askAI
    case moveToRegion(TripEntry)

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
        case .askAI:
            return "askAI"
        case .moveToRegion(let entry):
            return "moveToRegion_\(entry.id)"
        }
    }
}

struct TripDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @EnvironmentObject var flightStore: FlightStore
    @StateObject private var aiService = AIItineraryService.shared
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    let onFlightSelected: ((Flight, Trip) -> Void)?
    @State private var presentedSheet: PresentedSheet?

    init(trip: Trip, onFlightSelected: ((Flight, Trip) -> Void)? = nil) {
        self.trip = trip
        self.onFlightSelected = onFlightSelected
        _destinationTimeZone = State(initialValue: trip.destinationTimeZone)
    }
    
    private var entries: [TripEntry] {
        tripStore.getEntries(for: trip.id).sortedByTimestamp()
    }

    private var groupedEntries: [(Date, [TripEntry])] {
        tripStore.getEntriesGroupedByDay(for: trip.id, in: destinationTimeZone)
    }

    private var groupedByRegionAndDay: [(regionName: String, regionOrder: Int, days: [(Date, [TripEntry])])] {
        tripStore.getEntriesGroupedByRegionAndDay(for: trip.id, in: destinationTimeZone)
    }

    private var groupedByRegion: [(regionName: String, regionOrder: Int, entryCount: Int)] {
        tripStore.getEntriesGroupedByRegion(for: trip.id)
    }

    private var hasRegions: Bool {
        groupedByRegion.count > 1 || (groupedByRegion.count == 1 && groupedByRegion.first?.regionName != "Unassigned")
    }

    private var previewEntries: [TripEntry] {
        entries.filter { $0.isPreview }
    }

    private var hasPreview: Bool {
        !previewEntries.isEmpty
    }

    @State private var selectedDayIndex: Int = 0
    @State private var selectedRegionIndex: Int? = nil
    @State private var collapsedRegions: Set<String> = []
    @State private var destinationTimeZone: TimeZone
    @State private var showRegionDetectionBanner = false
    @State private var isDetectingRegions = false
    @State private var longPressedEntry: TripEntry? = nil
    @State private var showEntryActionSheet = false
    @State private var regionToRename: String? = nil
    @State private var showRenameRegionAlert = false
    @State private var newRegionNameInput = ""

    var body: some View {
        NavigationView {
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Trip header (map extends behind navigation bar)
                            TripHeaderView(trip: trip, entries: entries)
                                .ignoresSafeArea(edges: .top)

                            // Region selector banner (if multiple regions exist)
                            if hasRegions && !entries.isEmpty {
                                RegionSelectorBanner(
                                    groupedByRegion: groupedByRegion,
                                    selectedRegionIndex: $selectedRegionIndex,
                                    onRegionSelected: { regionIndex in
                                        withAnimation {
                                            selectedRegionIndex = regionIndex
                                            let regionName = groupedByRegion[regionIndex].regionName
                                            proxy.scrollTo("region_\(regionIndex)", anchor: .top)
                                        }
                                    }
                                )
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                                .background(themeManager.currentTheme.colors.background)
                            }

                            // Region detection banner
                            if showRegionDetectionBanner {
                                RegionDetectionBannerView(
                                    isDetecting: isDetectingRegions,
                                    onDetect: { detectRegions() },
                                    onDismiss: {
                                        UserDefaults.standard.set(true, forKey: "regionBannerDismissed_\(trip.id)")
                                        withAnimation { showRegionDetectionBanner = false }
                                    }
                                )
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 4)
                            }

                            // Timeline content
                            if entries.isEmpty {
                                EmptyTimelineView(onAddEntry: { presentedSheet = .addEntryMenu })
                            } else {
                                if hasRegions {
                                    // Region-based timeline
                                    RegionTimelineView(
                                        groupedByRegionAndDay: groupedByRegionAndDay,
                                        collapsedRegions: $collapsedRegions,
                                        timeZone: destinationTimeZone,
                                        onEntryTap: { entry in
                                            handleEntryTap(entry)
                                        },
                                        onEntryLongPress: { entry in
                                            handleEntryLongPress(entry)
                                        },
                                        onRegionLongPress: { regionName in
                                            regionToRename = regionName
                                            newRegionNameInput = regionName
                                            showRenameRegionAlert = true
                                        }
                                    )
                                } else {
                                    // Day-based timeline (original)
                                    TimelineView(
                                        groupedEntries: groupedEntries,
                                        selectedDayIndex: selectedDayIndex,
                                        timeZone: destinationTimeZone,
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
                    }
                }

                // Preview accept/reject bar or floating add button
                VStack {
                    Spacer()

                    if hasPreview {
                        // Preview action bar
                        previewActionBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // Regular floating add button
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

                // AI Generation Loading Overlay (hidden for streaming)
                // Activities appear directly in timeline instead
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                            presentedSheet = .askAI
                        }
                    }
                }
                .environmentObject(themeManager)
            case .askAI:
                AskAIPlannerView(trip: trip) { activity in
                    handleStreamingActivity(activity)
                }
                .environmentObject(themeManager)
                .environmentObject(tripStore)
            case .moveToRegion(let entry):
                RegionPickerView(
                    entry: entry,
                    existingRegions: groupedByRegion,
                    tripId: trip.id
                )
                .environmentObject(themeManager)
                .environmentObject(tripStore)
            }
        }
        .confirmationDialog("", isPresented: $showEntryActionSheet, presenting: longPressedEntry) { entry in
            Button("Edit Activity") { presentedSheet = .editEntry(entry) }
            if hasRegions {
                Button("Move to Region...") { presentedSheet = .moveToRegion(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(entry.title)
        }
        .alert("Rename Region", isPresented: $showRenameRegionAlert) {
            TextField("Region name", text: $newRegionNameInput)
            Button("Rename") { renameRegion(from: regionToRename, to: newRegionNameInput) }
            Button("Cancel", role: .cancel) { regionToRename = nil }
        } message: {
            Text("Enter a new name for this region")
        }
        .onAppear {
            // Make navigation bar completely transparent
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance

            Task {
                await tripStore.fetchEntriesForTrip(trip.id)
                await migrateFlightEntries()
                await MainActor.run { checkIfShouldShowRegionBanner() }
                await resolveDestinationTimeZone()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleStreamingActivity(_ activity: ItineraryItem) {
        Task {
            // Convert single activity to preview trip entry
            let entry = activity.toTripEntry(tripId: trip.id, isPreview: true)

            // Add to trip store - TripStore is @ObservableObject so view will update automatically
            let result = await tripStore.addEntry(entry)

            if case .failure(let error) = result {
                print("Failed to add streaming activity: \(error.localizedDescription)")
            }
        }
    }

    private func handleProcessedItinerary(_ parsedItinerary: ParsedItinerary) {
        Task {
            do {
                // Convert all items to PREVIEW trip entries
                let tripEntries = parsedItinerary.toTripEntries(tripId: trip.id, isPreview: true)

                // Add each preview entry to the trip
                for entry in tripEntries {
                    let result = await tripStore.addEntry(entry)
                    if case .failure(let error) = result {
                        print("Failed to add preview entry: \(error.localizedDescription)")
                        return
                    }
                }

                await MainActor.run {
                    presentedSheet = nil
                }

            } catch {
                print("Failed to add entries: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Preview Action Bar

    private var previewActionBar: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                Text("AI Generated \(previewEntries.count) Activities")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                HStack(spacing: 12) {
                    Button {
                        rejectPreviews()
                    } label: {
                        HStack {
                            Image(systemName: "xmark")
                            Text("Reject")
                        }
                    }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)

                    Button {
                        acceptPreviews()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Accept All")
                        }
                    }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.currentTheme.colors.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(themeManager.currentTheme.colors.background)
    }

    // MARK: - AI Generation Loading Overlay

    private var aiGenerationLoadingOverlay: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Loading card
            VStack(spacing: 24) {
                // Animated sparkles
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(themeManager.currentTheme.colors.primary.opacity(0.8))
                            .rotationEffect(.degrees(Double(index) * 120))
                            .scaleEffect(1.0 + Double(index) * 0.1)
                    }
                }
                .frame(height: 60)

                VStack(spacing: 12) {
                    Text("Creating Your Itinerary")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.text)

                    Text(aiService.currentStatus)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(themeManager.currentTheme.colors.surface)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(themeManager.currentTheme.colors.primary)
                                .frame(width: geometry.size.width * aiService.processingProgress, height: 8)
                                .animation(.easeInOut, value: aiService.processingProgress)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(themeManager.currentTheme.colors.background)
            )
            .shadow(
                color: Color.black.opacity(0.2),
                radius: 20,
                x: 0,
                y: 10
            )
            .padding(.horizontal, 40)
        }
    }

    private func acceptPreviews() {
        Task {
            print("🎯 Accepting \(previewEntries.count) preview entries...")

            // Convert all preview entries to permanent entries
            for entry in previewEntries {
                // Create a copy with isPreview = false
                let permanentEntry = TripEntry(
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
                    flightId: entry.flightId,
                    isPreview: false,
                    regionName: entry.regionName,
                    regionOrder: entry.regionOrder,
                    isRegionAIGenerated: entry.isRegionAIGenerated,
                    createdAt: entry.createdAt,
                    updatedAt: Date()
                )

                // Update the entry
                let result = await tripStore.updateEntry(permanentEntry)
                switch result {
                case .success:
                    print("✅ Accepted entry: \(entry.title)")
                case .failure(let error):
                    print("❌ Failed to accept entry: \(error)")
                }
            }

            // UI will update automatically via TripStore's @Published properties
            await MainActor.run {
                print("✅ All previews accepted")
            }
        }
    }

    private func rejectPreviews() {
        Task {
            // Delete all preview entries
            for entry in previewEntries {
                _ = await tripStore.deleteEntry(entry.id, tripId: entry.tripId)
            }

            // UI will update automatically via TripStore's @Published properties
            await MainActor.run {
                print("✅ All previews rejected")
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
        longPressedEntry = entry
        showEntryActionSheet = true
    }

    private func resolveDestinationTimeZone() async {
        // Already stored — nothing to do
        guard trip.timeZoneIdentifier == nil else { return }
        guard let lat = trip.latitude, let lng = trip.longitude else { return }
        let location = CLLocation(latitude: lat, longitude: lng)
        let geocoder = CLGeocoder()
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
              let tz = placemarks.first?.timeZone else { return }
        await MainActor.run { destinationTimeZone = tz }
        // Persist so future loads skip geocoding entirely
        let updatedTrip = Trip(
            id: trip.id, title: trip.title, destination: trip.destination,
            destinationCode: trip.destinationCode, state: trip.state, country: trip.country,
            startDate: trip.startDate, endDate: trip.endDate, description: trip.description,
            coverImageURL: trip.coverImageURL, latitude: trip.latitude, longitude: trip.longitude,
            timeZoneIdentifier: tz.identifier,
            createdAt: trip.createdAt, updatedAt: Date()
        )
        _ = await tripStore.updateTrip(updatedTrip)
    }

    private func checkIfShouldShowRegionBanner() {
        let dismissed = UserDefaults.standard.bool(forKey: "regionBannerDismissed_\(trip.id)")
        if !dismissed && entries.count >= 5 && !hasRegions {
            showRegionDetectionBanner = true
        }
    }

    private func detectRegions() {
        isDetectingRegions = true
        Task {
            let regionGroups = await TripRegionService.shared.detectRegions(for: entries, trip: trip)
            let updatedEntries = TripRegionService.shared.assignRegionsToEntries(entries, regions: regionGroups)
            for entry in updatedEntries {
                _ = await tripStore.updateEntryRegion(
                    entry.id,
                    tripId: entry.tripId,
                    regionName: entry.regionName,
                    regionOrder: entry.regionOrder,
                    isAIGenerated: true
                )
            }
            await MainActor.run {
                isDetectingRegions = false
                withAnimation { showRegionDetectionBanner = false }
            }
        }
    }

    private func renameRegion(from oldName: String?, to newName: String) {
        guard let oldName = oldName, !newName.isEmpty, newName != oldName else {
            regionToRename = nil
            return
        }
        let entriesToRename = entries.filter { $0.regionName == oldName }
        Task {
            for entry in entriesToRename {
                _ = await tripStore.updateEntryRegion(
                    entry.id,
                    tripId: entry.tripId,
                    regionName: newName,
                    regionOrder: entry.regionOrder,
                    isAIGenerated: entry.isRegionAIGenerated
                )
            }
        }
        regionToRename = nil
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
                    isPreview: entry.isPreview,
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
    let entries: [TripEntry]

    var body: some View {
        VStack(spacing: 16) {
            // Trip image
            TripHeaderImageView(trip: trip, entries: entries)
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
    let entries: [TripEntry]

    @State private var routes: [RouteSegment] = []
    @State private var showingExpandedMap = false
    @State private var isLoadingRoutes = false

    // Track entries for change detection
    private var entriesSignature: String {
        entries.map { "\($0.id)-\($0.latitude ?? 0)-\($0.longitude ?? 0)" }.joined(separator: ",")
    }

    // Simplified entries signature for less frequent updates
    private var entriesCountSignature: String {
        "\(entries.count)-\(entries.filter { $0.hasLocation }.count)"
    }

    // Get entries with locations, sorted chronologically
    private var entriesWithLocations: [(Int, TripEntry)] {
        entries.filter { $0.hasLocation }
            .enumerated()
            .map { ($0.offset + 1, $0.element) }
    }

    // Create path segments between consecutive entries
    private var pathSegments: [(TripEntry, TripEntry)] {
        guard entriesWithLocations.count > 1 else { return [] }

        var segments: [(TripEntry, TripEntry)] = []
        for i in 0..<(entriesWithLocations.count - 1) {
            let current = entriesWithLocations[i].1
            let next = entriesWithLocations[i + 1].1
            segments.append((current, next))
        }
        return segments
    }

    // Route segment with color information
    struct RouteSegment: Identifiable {
        let id = UUID()
        let coordinates: [CLLocationCoordinate2D]
        let startColor: Color
        let endColor: Color
    }

    // Calculate map region to fit all markers
    private var mapRegion: MKCoordinateRegion {
        if entriesWithLocations.isEmpty {
            // No entry locations, center on trip destination
            if let lat = trip.latitude, let lng = trip.longitude {
                return MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
        } else {
            // Calculate bounds to fit all entry locations
            let coordinates = entriesWithLocations.compactMap { $0.1.coordinate }

            if coordinates.count == 1, let coord = coordinates.first {
                return MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            } else if coordinates.count > 1 {
                let minLat = coordinates.map { $0.latitude }.min() ?? 0
                let maxLat = coordinates.map { $0.latitude }.max() ?? 0
                let minLng = coordinates.map { $0.longitude }.min() ?? 0
                let maxLng = coordinates.map { $0.longitude }.max() ?? 0

                let centerLat = (minLat + maxLat) / 2
                let centerLng = (minLng + maxLng) / 2
                let spanLat = (maxLat - minLat) * 1.5  // Add 50% padding
                let spanLng = (maxLng - minLng) * 1.5

                return MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
                    span: MKCoordinateSpan(
                        latitudeDelta: max(spanLat, 0.02),
                        longitudeDelta: max(spanLng, 0.02)
                    )
                )
            }
        }

        // Fallback
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }

    var body: some View {
        if trip.latitude != nil && trip.longitude != nil || !entriesWithLocations.isEmpty {
            // Show map with numbered markers and route paths
            Map(initialPosition: .region(mapRegion)) {
                // Draw route paths with gradient colors
                ForEach(routes) { route in
                    // OPTIMIZATION: Group coordinates into chunks to reduce polyline count
                    let chunkSize = max(1, route.coordinates.count / 5)  // ~5 color segments per route (was 10)
                    let chunks = stride(from: 0, to: route.coordinates.count - 1, by: chunkSize)

                    ForEach(Array(chunks.enumerated()), id: \.offset) { index, startIdx in
                        let endIdx = min(startIdx + chunkSize + 1, route.coordinates.count)
                        if startIdx < route.coordinates.count && endIdx <= route.coordinates.count && endIdx > startIdx {
                            let progress = Double(index) / Double(max(1, route.coordinates.count / chunkSize))
                            let segmentColor = interpolateColor(
                                from: route.startColor,
                                to: route.endColor,
                                progress: progress
                            )

                            MapPolyline(coordinates: Array(route.coordinates[startIdx..<endIdx]))
                                .stroke(
                                    segmentColor.opacity(0.85),
                                    style: StrokeStyle(
                                        lineWidth: 4,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }
                    }
                }

                // Show numbered markers for each entry (on top of paths)
                ForEach(entriesWithLocations, id: \.1.id) { number, entry in
                    if let coordinate = entry.coordinate {
                        Annotation(entry.title, coordinate: coordinate) {
                            NumberedMarkerView(
                                number: number,
                                color: entry.entryType.swiftUIColor
                            )
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .mapControlVisibility(.hidden)
            .task {
                // Lazy load routes after a short delay to show map first
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second delay
                await fetchRoutes()
            }
            .onChange(of: entriesCountSignature) { _, _ in
                // Only refetch when entry count changes (not on every coordinate update)
                Task {
                    routes = []  // Clear existing routes
                    try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 second debounce
                    await fetchRoutes()
                }
            }
            .id(entriesCountSignature)
            .onTapGesture {
                showingExpandedMap = true
            }
            .overlay(
                // Overlays
                ZStack {
                    // Loading indicator
                    if isLoadingRoutes && routes.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                    Text("Loading routes...")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.7))
                                )
                                Spacer()
                            }
                            .padding(.bottom, 60)
                        }
                    }

                    // Tap indicator overlay
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Tap to expand")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                            .padding(12)
                        }
                    }
                }
            )
            .sheet(isPresented: $showingExpandedMap) {
                ExpandedMapView(
                    trip: trip,
                    entries: entries,
                    routes: routes,
                    entriesWithLocations: entriesWithLocations
                )
            }
        } else {
            // Fallback for trips without coordinates
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

    // Fetch actual routes between consecutive entries - OPTIMIZED
    private func fetchRoutes() async {
        // Skip if already loading
        guard !isLoadingRoutes else { return }

        // Skip if no segments
        guard !pathSegments.isEmpty else {
            routes = []
            return
        }

        // Skip if routes already loaded for current segments
        // (prevents unnecessary refetch when view appears again)
        if !routes.isEmpty && routes.count == pathSegments.count {
            return
        }

        await MainActor.run {
            isLoadingRoutes = true
        }

        print("🗺️ Fetching routes for \(pathSegments.count) segments...")

        // Fetch all routes in parallel for better performance
        await withTaskGroup(of: (Int, RouteSegment).self) { group in
            for (index, segment) in pathSegments.enumerated() {
                group.addTask {
                    return (index, await self.fetchSingleRoute(segment: segment))
                }
            }

            var fetchedRoutes: [(Int, RouteSegment)] = []
            for await result in group {
                fetchedRoutes.append(result)
            }

            // Sort by index to maintain order
            let sortedRoutes = fetchedRoutes.sorted { $0.0 < $1.0 }.map { $0.1 }

            await MainActor.run {
                self.routes = sortedRoutes
                self.isLoadingRoutes = false
                print("✅ Loaded \(sortedRoutes.count) routes")
            }
        }
    }

    // Fetch a single route segment with caching
    private func fetchSingleRoute(segment: (TripEntry, TripEntry)) async -> RouteSegment {
        let startEntry = segment.0
        let endEntry = segment.1

        guard let startCoord = startEntry.coordinate,
              let endCoord = endEntry.coordinate else {
            return RouteSegment(
                coordinates: [],
                startColor: startEntry.entryType.swiftUIColor,
                endColor: endEntry.entryType.swiftUIColor
            )
        }

        // Check cache first
        if let cached = await RouteCache.shared.getRoute(from: startEntry.id, to: endEntry.id) {
            print("✅ Using cached route: \(startEntry.title) → \(endEntry.title)")
            return RouteSegment(
                coordinates: cached.coordinates.map { $0.coordinate },
                startColor: startEntry.entryType.swiftUIColor,
                endColor: endEntry.entryType.swiftUIColor
            )
        }

        // Not in cache, fetch from Apple Maps
        print("🌐 Fetching route: \(startEntry.title) → \(endEntry.title)")

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: startCoord))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: endCoord))
        request.transportType = .automobile

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            if let route = response.routes.first {
                // Simplify coordinates - only use every Nth point for gradient
                let pointCount = route.polyline.pointCount
                var coordinates: [CLLocationCoordinate2D] = []

                if pointCount > 0 {
                    let points = route.polyline.points()
                    // OPTIMIZATION: Aggressively sample points to reduce rendering load
                    let step = max(1, pointCount / 30)  // Limit to ~30 points max (was 50)
                    for i in stride(from: 0, to: pointCount, by: step) {
                        coordinates.append(points[i].coordinate)
                    }
                    // Always include the last point
                    if pointCount > 1 && (pointCount - 1) % step != 0 {
                        coordinates.append(points[pointCount - 1].coordinate)
                    }
                }

                // Save to cache
                await RouteCache.shared.saveRoute(
                    from: startEntry.id,
                    to: endEntry.id,
                    coordinates: coordinates,
                    startColor: startEntry.entryType.color,
                    endColor: endEntry.entryType.color
                )

                return RouteSegment(
                    coordinates: coordinates,
                    startColor: startEntry.entryType.swiftUIColor,
                    endColor: endEntry.entryType.swiftUIColor
                )
            }
        } catch {
            // Silently fall back to straight line
        }

        // Fallback to straight line (don't cache this)
        return RouteSegment(
            coordinates: [startCoord, endCoord],
            startColor: startEntry.entryType.swiftUIColor,
            endColor: endEntry.entryType.swiftUIColor
        )
    }

    // Interpolate between two colors based on progress (0.0 to 1.0)
    private func interpolateColor(from startColor: Color, to endColor: Color, progress: Double) -> Color {
        // Extract RGB components
        let startUIColor = UIColor(startColor)
        let endUIColor = UIColor(endColor)

        var startRed: CGFloat = 0, startGreen: CGFloat = 0, startBlue: CGFloat = 0, startAlpha: CGFloat = 0
        var endRed: CGFloat = 0, endGreen: CGFloat = 0, endBlue: CGFloat = 0, endAlpha: CGFloat = 0

        startUIColor.getRed(&startRed, green: &startGreen, blue: &startBlue, alpha: &startAlpha)
        endUIColor.getRed(&endRed, green: &endGreen, blue: &endBlue, alpha: &endAlpha)

        // Interpolate each component
        let red = startRed + (endRed - startRed) * progress
        let green = startGreen + (endGreen - startGreen) * progress
        let blue = startBlue + (endBlue - startBlue) * progress
        let alpha = startAlpha + (endAlpha - startAlpha) * progress

        return Color(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(alpha)
        )
    }
}

// MARK: - Region Selector Banner
struct RegionSelectorBanner: View {
    @EnvironmentObject var themeManager: ThemeManager

    let groupedByRegion: [(regionName: String, regionOrder: Int, entryCount: Int)]
    @Binding var selectedRegionIndex: Int?
    let onRegionSelected: (Int) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(groupedByRegion.enumerated()), id: \.offset) { index, regionGroup in
                        let isSelected = index == selectedRegionIndex
                        let (regionName, _, entryCount) = regionGroup

                        Button {
                            onRegionSelected(index)
                        } label: {
                            HStack(spacing: 12) {
                                // Location pin icon
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(isSelected ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                                    .frame(width: 20)

                                // Region info
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(regionName)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(themeManager.currentTheme.colors.text)

                                    Text("\(entryCount) \(entryCount == 1 ? "activity" : "activities")")
                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(minWidth: 180)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        isSelected
                                            ? themeManager.currentTheme.colors.primary.opacity(0.12)
                                            : (themeManager.currentTheme == .dark
                                                ? Color(white: 0.15)
                                                : Color(white: 0.96))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        isSelected ? themeManager.currentTheme.colors.primary.opacity(0.3) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id("region_selector_\(index)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selectedRegionIndex) { _, newValue in
                if let newValue = newValue {
                    withAnimation {
                        scrollProxy.scrollTo("region_selector_\(newValue)", anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Day Selector Banner
struct DaySelectorBanner: View {
    @EnvironmentObject var themeManager: ThemeManager

    let groupedEntries: [(Date, [TripEntry])]
    @Binding var selectedDayIndex: Int
    let onDaySelected: (Int) -> Void

    private func dayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func dateRange(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(groupedEntries.enumerated()), id: \.offset) { index, dayGroup in
                        let (date, entries) = dayGroup
                        let isSelected = index == selectedDayIndex

                        Button {
                            onDaySelected(index)
                        } label: {
                            HStack(spacing: 12) {
                                // Calendar icon
                                Image(systemName: "calendar")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(isSelected ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                                    .frame(width: 20)

                                // Day info
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dayTitle(for: date))
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(themeManager.currentTheme.colors.text)

                                    Text(dateRange(for: date))
                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }

                                Spacer()

                                // Activity count badge
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 10, weight: .medium))
                                    Text("\(entries.count)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(isSelected ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(minWidth: 200)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        isSelected
                                            ? themeManager.currentTheme.colors.primary.opacity(0.12)
                                            : (themeManager.currentTheme == .dark
                                                ? Color(white: 0.15)
                                                : Color(white: 0.96))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        isSelected ? themeManager.currentTheme.colors.primary.opacity(0.3) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id("day_selector_\(index)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selectedDayIndex) { _, newValue in
                withAnimation {
                    scrollProxy.scrollTo("day_selector_\(newValue)", anchor: .center)
                }
            }
        }
    }
}

// MARK: - Region Timeline View
struct RegionTimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let groupedByRegionAndDay: [(regionName: String, regionOrder: Int, days: [(Date, [TripEntry])])]
    @Binding var collapsedRegions: Set<String>
    let timeZone: TimeZone
    let onEntryTap: (TripEntry) -> Void
    let onEntryLongPress: (TripEntry) -> Void
    let onRegionLongPress: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(groupedByRegionAndDay.enumerated()), id: \.offset) { regionIndex, regionGroup in
                let (regionName, _, days) = regionGroup
                let legKey = "\(regionName)_\(regionIndex)"
                let isCollapsed = collapsedRegions.contains(legKey)

                // Calculate date range for region
                let dateRange = calculateDateRange(for: days, in: timeZone)
                let totalEntries = days.flatMap { $0.1 }.count

                // Region header
                RegionHeaderView(
                    regionName: regionName,
                    dateRange: dateRange,
                    totalDays: days.count,
                    totalEntries: totalEntries,
                    isCollapsed: isCollapsed,
                    onToggle: {
                        withAnimation {
                            if isCollapsed {
                                collapsedRegions.remove(legKey)
                            } else {
                                collapsedRegions.insert(legKey)
                            }
                        }
                    },
                    onLongPress: { onRegionLongPress(regionName) }
                )
                .id("region_\(regionIndex)")
                .padding(.horizontal, 20)
                .padding(.top, regionIndex == 0 ? 20 : 32)
                .padding(.bottom, 16)

                // Days within region (only if not collapsed)
                if !isCollapsed {
                    ForEach(Array(days.enumerated()), id: \.element.0) { dayIndex, dayGroup in
                        let (date, entries) = dayGroup

                        // Day header
                        TimelineDayHeader(date: date, entryCount: entries.count, timeZone: timeZone)
                            .padding(.horizontal, 20)
                            .padding(.top, dayIndex == 0 ? 0 : 24)
                            .padding(.bottom, 12)

                        // Entries for this day
                        ForEach(Array(entries.enumerated()), id: \.element.id) { entryIndex, entry in
                            let isLast = entryIndex == entries.count - 1 && dayIndex == days.count - 1

                            TimelineEntryView(
                                entry: entry,
                                isLast: isLast,
                                timeZone: timeZone,
                                onTap: { onEntryTap(entry) },
                                onLongPress: { onEntryLongPress(entry) }
                            )
                            .padding(.horizontal, 20)
                            .transition(
                                entry.isPreview
                                    ? .asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .identity
                                    )
                                    : .identity
                            )
                        }
                    }
                }
            }

            // Bottom padding
            Color.clear
                .frame(height: 100)
        }
    }

    private func calculateDateRange(for days: [(Date, [TripEntry])], in timeZone: TimeZone) -> String {
        guard !days.isEmpty else { return "" }

        let dates = days.map { $0.0 }.sorted()
        guard let firstDate = dates.first, let lastDate = dates.last else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = timeZone

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        if cal.isDate(firstDate, inSameDayAs: lastDate) {
            return formatter.string(from: firstDate)
        } else {
            return "\(formatter.string(from: firstDate)) - \(formatter.string(from: lastDate))"
        }
    }
}

// MARK: - Region Header View
struct RegionHeaderView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let regionName: String
    let dateRange: String
    let totalDays: Int
    let totalEntries: Int
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 12) {
                // Location icon
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(themeManager.currentTheme.colors.primary)

                // Region info
                VStack(alignment: .leading, spacing: 4) {
                    Text(regionName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.colors.text)

                    HStack(spacing: 8) {
                        Text(dateRange)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                        Text("•")
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                        Text("\(totalDays) \(totalDays == 1 ? "day" : "days")")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                        Text("•")
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                        Text("\(totalEntries) \(totalEntries == 1 ? "activity" : "activities")")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.currentTheme.colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() }
        )
    }
}

// MARK: - Timeline View
struct TimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let groupedEntries: [(Date, [TripEntry])]
    let selectedDayIndex: Int
    let timeZone: TimeZone
    let onEntryTap: (TripEntry) -> Void
    let onEntryLongPress: (TripEntry) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(groupedEntries.enumerated()), id: \.offset) { dayIndex, dayGroup in
                let (date, entries) = dayGroup

                // Day header with ID for scrolling
                TimelineDayHeader(date: date, entryCount: entries.count, timeZone: timeZone)
                    .id("day_\(dayIndex)")
                    .padding(.horizontal, 20)
                    .padding(.top, dayIndex == 0 ? 20 : 32)
                    .padding(.bottom, 16)

                // Entries for this day
                ForEach(Array(entries.enumerated()), id: \.element.id) { entryIndex, entry in
                    TimelineEntryView(
                        entry: entry,
                        isLast: entryIndex == entries.count - 1 && dayIndex == groupedEntries.count - 1,
                        timeZone: timeZone,
                        onTap: { onEntryTap(entry) },
                        onLongPress: { onEntryLongPress(entry) }
                    )
                    .padding(.horizontal, 20)
                    .transition(
                        entry.isPreview
                            ? .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .identity
                            )
                            : .identity
                    )
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
    let timeZone: TimeZone

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.timeZone = timeZone
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
    let timeZone: TimeZone
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
            TimelineEntryCard(entry: entry, timeZone: timeZone, onTap: onTap, onLongPress: onLongPress)
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

// MARK: - Animated AI Gradient (Arc-style)
struct AnimatedAIGradient: View {
    @State private var animationPhase: CGFloat = 0

    let colors: [Color] = [
        Color(red: 0.4, green: 0.2, blue: 0.8), // Purple
        Color(red: 0.2, green: 0.4, blue: 0.9), // Blue
        Color(red: 0.6, green: 0.3, blue: 0.9), // Purple-pink
        Color(red: 0.3, green: 0.5, blue: 1.0)  // Light blue
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Moving gradient
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .hueRotation(.degrees(animationPhase * 60))
                .blur(radius: 30)
                .opacity(0.15)

                // Animated overlay shimmer
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        .white.opacity(0.2),
                        .clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: -geometry.size.width + (geometry.size.width * 2 * animationPhase))
            }
        }
        .onAppear {
            withAnimation(
                .linear(duration: 2.5)
                .repeatForever(autoreverses: false)
            ) {
                animationPhase = 1.0
            }
        }
    }
}

// MARK: - Timeline Entry Card
struct TimelineEntryCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    let entry: TripEntry
    let timeZone: TimeZone
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = timeZone
        return formatter.string(from: entry.timestamp)
    }

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

                    // AI Preview badge with gradient
                    if entry.isPreview {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(.caption2, design: .monospaced))
                            Text("AI")
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.5, green: 0.3, blue: 0.9),
                                    Color(red: 0.3, green: 0.5, blue: 1.0)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.15),
                                    Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.15)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(4)
                    }
                }

                Spacer()

                Text(timeText)
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
        .background(
            ZStack {
                // Base background
                themeManager.currentTheme.colors.surface

                // Animated gradient for AI preview
                if entry.isPreview {
                    AnimatedAIGradient()
                }
            }
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    entry.isPreview
                        ? LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.4, green: 0.2, blue: 0.8),
                                Color(red: 0.3, green: 0.5, blue: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            gradient: Gradient(colors: [
                                themeManager.currentTheme.colors.border,
                                themeManager.currentTheme.colors.border
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                    lineWidth: entry.isPreview ? 2 : 1
                )
        )
        .shadow(
            color: entry.isPreview ? Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.2) : .clear,
            radius: 8,
            x: 0,
            y: 2
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
        case .manual, .importFiles, .askAI: return true
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

// MARK: - Numbered Marker View
struct NumberedMarkerView: View {
    let number: Int
    let color: Color

    var body: some View {
        ZStack {
            // Shadow circle
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 34, height: 34)
                .offset(y: 2)

            // Main marker circle
            Circle()
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )

            // Number text
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - TripEntryType Color Extension
extension TripEntryType {
    var swiftUIColor: Color {
        switch self {
        case .food:
            return .orange
        case .activity:
            return .purple
        case .sightseeing:
            return .blue
        case .accommodation:
            return .green
        case .transportation:
            return .red
        case .flight:
            return .cyan
        case .shopping:
            return .pink
        case .note:
            return .gray
        case .photo:
            return .yellow
        }
    }
}

// MARK: - Expanded Map View
struct ExpandedMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    let trip: Trip
    let entries: [TripEntry]
    let routes: [TripHeaderImageView.RouteSegment]
    let entriesWithLocations: [(Int, TripEntry)]

    // Calculate map region to fit all markers
    private var mapRegion: MKCoordinateRegion {
        if entriesWithLocations.isEmpty {
            if let lat = trip.latitude, let lng = trip.longitude {
                return MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
        } else {
            let coordinates = entriesWithLocations.compactMap { $0.1.coordinate }

            if coordinates.count == 1, let coord = coordinates.first {
                return MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            } else if coordinates.count > 1 {
                let minLat = coordinates.map { $0.latitude }.min() ?? 0
                let maxLat = coordinates.map { $0.latitude }.max() ?? 0
                let minLng = coordinates.map { $0.longitude }.min() ?? 0
                let maxLng = coordinates.map { $0.longitude }.max() ?? 0

                let centerLat = (minLat + maxLat) / 2
                let centerLng = (minLng + maxLng) / 2
                let spanLat = (maxLat - minLat) * 1.5
                let spanLng = (maxLng - minLng) * 1.5

                return MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
                    span: MKCoordinateSpan(
                        latitudeDelta: max(spanLat, 0.02),
                        longitudeDelta: max(spanLng, 0.02)
                    )
                )
            }
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }

    var body: some View {
        NavigationView {
            // Full screen map
            Map(initialPosition: .region(mapRegion)) {
                // Draw route paths with gradient colors - OPTIMIZED
                ForEach(routes) { route in
                    // Group coordinates into chunks to reduce polyline count
                    let chunkSize = max(1, route.coordinates.count / 5)  // ~5 color segments (was 10)
                    let chunks = stride(from: 0, to: route.coordinates.count - 1, by: chunkSize)

                    ForEach(Array(chunks.enumerated()), id: \.offset) { index, startIdx in
                        let endIdx = min(startIdx + chunkSize + 1, route.coordinates.count)
                        if startIdx < route.coordinates.count && endIdx <= route.coordinates.count && endIdx > startIdx {
                            let progress = Double(index) / Double(max(1, route.coordinates.count / chunkSize))
                            let segmentColor = interpolateColor(
                                from: route.startColor,
                                to: route.endColor,
                                progress: progress
                            )

                            MapPolyline(coordinates: Array(route.coordinates[startIdx..<endIdx]))
                                .stroke(
                                    segmentColor.opacity(0.85),
                                    style: StrokeStyle(
                                        lineWidth: 4,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }
                    }
                }

                // Show numbered markers
                ForEach(entriesWithLocations, id: \.1.id) { number, entry in
                    if let coordinate = entry.coordinate {
                        Annotation(entry.title, coordinate: coordinate) {
                            NumberedMarkerView(
                                number: number,
                                color: entry.entryType.swiftUIColor
                            )
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .mapControlVisibility(.visible)
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom) {
                // Navigate button at bottom center
                HStack {
                    Spacer()

                    Menu {
                        Button {
                            openInAppleMaps()
                        } label: {
                            Label("Navigate in Apple Maps", systemImage: "map.fill")
                        }

                        Button {
                            openInGoogleMaps()
                        } label: {
                            Label("Navigate in Google Maps", systemImage: "globe.americas.fill")
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 20, weight: .semibold))

                            Text("Navigate")
                                .font(.system(.body, design: .monospaced, weight: .semibold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }

                    Spacer()
                }
                .padding(.bottom, 20)
                .background(Color.clear)
            }
            .navigationTitle(trip.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title3))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }
            }
        }
    }

    // Open trip itinerary in Apple Maps with all waypoints
    private func openInAppleMaps() {
        guard !entriesWithLocations.isEmpty else { return }

        let locations = entriesWithLocations.map { $0.1 }

        // Create map items for all locations
        let mapItems = locations.compactMap { entry -> MKMapItem? in
            guard let coordinate = entry.coordinate else { return nil }
            let placemark = MKPlacemark(coordinate: coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = entry.title
            return mapItem
        }

        guard !mapItems.isEmpty else { return }

        // Open with directions for sequential navigation
        if mapItems.count == 1 {
            // Single location - just open it
            mapItems[0].openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        } else {
            // Multiple locations - open with first as destination
            // Note: Apple Maps doesn't support multiple waypoints in URL scheme well
            // So we'll open directions to the first location with a note
            MKMapItem.openMaps(
                with: mapItems,
                launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
                    MKLaunchOptionsShowsTrafficKey: true
                ]
            )
        }

        print("🗺️ Opened \(mapItems.count) locations in Apple Maps")
    }

    // Open trip itinerary in Google Maps with all waypoints
    private func openInGoogleMaps() {
        guard !entriesWithLocations.isEmpty else { return }

        let locations = entriesWithLocations.map { $0.1 }.compactMap { $0.coordinate }
        guard !locations.isEmpty else { return }

        // Google Maps URL scheme on iOS doesn't support waypoints reliably
        // Always use web URL which works in both app and browser
        openGoogleMapsWeb(locations: locations)
    }

    // Open Google Maps with waypoints (works for both app and web)
    private func openGoogleMapsWeb(locations: [CLLocationCoordinate2D]) {
        guard !locations.isEmpty else { return }

        if locations.count == 1 {
            // Single location - direct navigation
            let coord = locations[0]
            let urlString = "https://www.google.com/maps/dir/?api=1&destination=\(coord.latitude),\(coord.longitude)&travelmode=driving"

            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
                print("🌐 Opened 1 location in Google Maps")
            }
        } else {
            // Multiple locations - use dir with all coordinates in path
            // Format: /dir/origin/waypoint1/waypoint2/destination
            var pathComponents: [String] = []

            for location in locations {
                pathComponents.append("\(location.latitude),\(location.longitude)")
            }

            let path = pathComponents.joined(separator: "/")
            let urlString = "https://www.google.com/maps/dir/\(path)"

            // URL encode the string properly
            if let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: encodedString) {
                UIApplication.shared.open(url)
                print("🌐 Opened \(locations.count) locations in Google Maps: \(pathComponents.joined(separator: " → "))")
            }
        }
    }

    // Interpolate between two colors based on progress (0.0 to 1.0)
    private func interpolateColor(from startColor: Color, to endColor: Color, progress: Double) -> Color {
        let startUIColor = UIColor(startColor)
        let endUIColor = UIColor(endColor)

        var startRed: CGFloat = 0, startGreen: CGFloat = 0, startBlue: CGFloat = 0, startAlpha: CGFloat = 0
        var endRed: CGFloat = 0, endGreen: CGFloat = 0, endBlue: CGFloat = 0, endAlpha: CGFloat = 0

        startUIColor.getRed(&startRed, green: &startGreen, blue: &startBlue, alpha: &startAlpha)
        endUIColor.getRed(&endRed, green: &endGreen, blue: &endBlue, alpha: &endAlpha)

        let red = startRed + (endRed - startRed) * progress
        let green = startGreen + (endGreen - startGreen) * progress
        let blue = startBlue + (endBlue - startBlue) * progress
        let alpha = startAlpha + (endAlpha - startAlpha) * progress

        return Color(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(alpha)
        )
    }
}

// MARK: - Region Detection Banner

struct RegionDetectionBannerView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let isDetecting: Bool
    let onDetect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(themeManager.currentTheme.colors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Organize by regions?")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                Text("Group activities by location automatically")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }

            Spacer()

            if isDetecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.85)
            } else {
                HStack(spacing: 8) {
                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    Button(action: onDetect) {
                        Text("Detect")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(themeManager.currentTheme.colors.primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.currentTheme.colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(themeManager.currentTheme.colors.primary.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Region Picker View

struct RegionPickerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss

    let entry: TripEntry
    let existingRegions: [(regionName: String, regionOrder: Int, entryCount: Int)]
    let tripId: String

    @State private var showNewRegionField = false
    @State private var newRegionName = ""
    @State private var isUpdating = false

    var body: some View {
        NavigationView {
            List {
                // Existing regions
                if !existingRegions.isEmpty {
                    Section("Existing Regions") {
                        ForEach(Array(existingRegions.enumerated()), id: \.offset) { _, region in
                            Button {
                                moveEntry(to: region.regionName, order: region.regionOrder)
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(themeManager.currentTheme.colors.primary)
                                    Text(region.regionName)
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                    Spacer()
                                    if entry.regionName == region.regionName {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(themeManager.currentTheme.colors.primary)
                                    }
                                }
                            }
                        }
                    }
                }

                // New region option
                Section("New Region") {
                    if showNewRegionField {
                        HStack {
                            TextField("Region name", text: $newRegionName)
                            Button("Add") {
                                let nextOrder = (existingRegions.map { $0.regionOrder }.max() ?? -1) + 1
                                moveEntry(to: newRegionName, order: nextOrder)
                            }
                            .disabled(newRegionName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .foregroundColor(themeManager.currentTheme.colors.primary)
                        }
                    } else {
                        Button {
                            showNewRegionField = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(themeManager.currentTheme.colors.primary)
                                Text("Create new region")
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                            }
                        }
                    }
                }

                // Remove from region
                if entry.regionName != nil {
                    Section {
                        Button(role: .destructive) {
                            moveEntry(to: nil, order: nil)
                        } label: {
                            HStack {
                                Image(systemName: "minus.circle.fill")
                                Text("Remove from region")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move to Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isUpdating {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                }
            }
        }
    }

    private func moveEntry(to regionName: String?, order: Int?) {
        isUpdating = true
        Task {
            _ = await tripStore.updateEntryRegion(
                entry.id,
                tripId: tripId,
                regionName: regionName,
                regionOrder: order,
                isAIGenerated: false
            )
            await MainActor.run {
                isUpdating = false
                dismiss()
            }
        }
    }
}

#Preview {
    TripDetailView(trip: Trip.sample)
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}