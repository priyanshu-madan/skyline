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

    private var previewEntries: [TripEntry] {
        entries.filter { $0.isPreview }
    }

    private var hasPreview: Bool {
        !previewEntries.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        // Trip header (map extends behind navigation bar)
                        TripHeaderView(trip: trip, entries: entries)
                            .ignoresSafeArea(edges: .top)

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
            }
        }
        .id(refreshID)
        .onAppear {
            // Make navigation bar completely transparent
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance

            Task {
                await tripStore.fetchEntriesForTrip(trip.id)
                await migrateFlightEntries()
                refreshID = UUID()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleStreamingActivity(_ activity: ItineraryItem) {
        Task {
            // Convert single activity to preview trip entry
            let entry = activity.toTripEntry(tripId: trip.id, isPreview: true)

            // Add to trip store
            let result = await tripStore.addEntry(entry)

            if case .failure(let error) = result {
                print("Failed to add streaming activity: \(error.localizedDescription)")
            } else {
                // Refresh UI to show new activity
                await MainActor.run {
                    refreshID = UUID()
                }
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
                    refreshID = UUID()
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
                    createdAt: entry.createdAt,
                    updatedAt: Date()
                )

                // Update the entry
                _ = await tripStore.updateEntry(permanentEntry)
            }

            await MainActor.run {
                refreshID = UUID()
            }
        }
    }

    private func rejectPreviews() {
        Task {
            // Delete all preview entries
            for entry in previewEntries {
                _ = await tripStore.deleteEntry(entry.id, tripId: entry.tripId)
            }

            await MainActor.run {
                refreshID = UUID()
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

                    // AI Preview badge
                    if entry.isPreview {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(.caption2, design: .monospaced))
                            Text("AI")
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                    }
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
        .background(
            entry.isPreview
                ? Color.orange.opacity(0.05)
                : themeManager.currentTheme.colors.surface
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    entry.isPreview
                        ? Color.orange.opacity(0.3)
                        : themeManager.currentTheme.colors.border,
                    lineWidth: entry.isPreview ? 2 : 1
                )
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

#Preview {
    TripDetailView(trip: Trip.sample)
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}