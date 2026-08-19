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
    case moveToRegion(TripEntry)
    case findPlaces

    var id: String {
        switch self {
        case .addEntry:
            return "addEntry"
        case .editEntry(let entry):
            return "editEntry_\(entry.id)"
        case .moveToRegion(let entry):
            return "moveToRegion_\(entry.id)"
        case .findPlaces:
            return "findPlaces"
        }
    }
}

struct TripDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @EnvironmentObject var flightStore: FlightStore
    @EnvironmentObject var placeStore: PlaceStore
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var fabDiameter: CGFloat = 56

    /// Motion is for orientation, never decoration. `nil` disables the
    /// animation outright when Reduce Motion is on — the pattern already used
    /// in ContentView and PlaceLogView.
    private var listAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    var body: some View {
        let theme = themeManager.currentTheme

        return NavigationStack {
            ZStack {
                // The page slab. Opaque and explicit: a transparent body would
                // borrow the DEVICE appearance behind the sheet.
                theme.colors.background
                    .ignoresSafeArea()

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
                                        withAnimation(listAnimation) {
                                            selectedRegionIndex = regionIndex
                                            proxy.scrollTo("region_\(regionIndex)", anchor: .top)
                                        }
                                    }
                                )
                                .padding(.top, AppSpacing.md)
                                .padding(.bottom, AppSpacing.sm)
                            }

                            // Region detection banner
                            if showRegionDetectionBanner {
                                RegionDetectionBannerView(
                                    isDetecting: isDetectingRegions,
                                    onDetect: { detectRegions() },
                                    onDismiss: {
                                        UserDefaults.standard.set(true, forKey: "regionBannerDismissed_\(trip.id)")
                                        withAnimation(listAnimation) { showRegionDetectionBanner = false }
                                    }
                                )
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.top, AppSpacing.md)
                                .padding(.bottom, AppSpacing.xs)
                            }

                            // Places logged for this trip. Without this the
                            // trip screen says nothing after the verdict deck,
                            // because places are not TripEntry rows.
                            TripPlacesSection(trip: trip) {
                                presentedSheet = .findPlaces
                            }
                            .environmentObject(themeManager)
                            .environmentObject(placeStore)

                            // Timeline content
                            if entries.isEmpty {
                                EmptyTimelineView(onAddEntry: { presentedSheet = .addEntry })
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
                    .skylineScrollEdges()
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
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                                presentedSheet = .addEntry
                            } label: {
                                Image(systemName: "plus")
                                    .font(AppTypography.mono(.title3, weight: .semibold))
                                    .frame(width: fabDiameter, height: fabDiameter)
                            }
                            // Let the system pick the glyph colour against the
                            // tint. `.white` on `colors.primary` is 2.6:1 in
                            // dark theme.
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.circle)
                            .tint(theme.colors.primary)
                            .accessibilityLabel(Text("Add activity"))
                            .padding(.trailing, AppSpacing.md)
                            .padding(.bottom, AppSpacing.lg)
                        }
                    }
                }
                .animation(listAnimation, value: hasPreview)

                // AI Generation Loading Overlay (hidden for streaming)
                // Activities appear directly in timeline instead
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            // Driven by the APP's theme, not the device appearance: the old
            // hardcoded `.dark` gave light bar glyphs over a light map.
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppTypography.mono(.body, weight: .semibold))
                    }
                    // Glass, because these float over a live map.
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Close"))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            presentedSheet = .findPlaces
                        } label: {
                            Label("Find Places from Photos", systemImage: "sparkles.rectangle.stack")
                        }

                        Divider()

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
                            .font(AppTypography.mono(.body, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Trip options"))
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
            case .findPlaces:
                TripPlaceDetectionView(trip: trip)
                    .environmentObject(themeManager)
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
    
    // MARK: - Preview Action Bar

    /// Floating chrome, not a docked toolbar. An `error`-coloured label on a
    /// glass button rather than a filled `red @ 10%` block — that block read as
    /// warm mud on dark and a Post-it note on light.
    private var previewActionBar: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.sm) {
            Text("AI suggested \(previewEntries.count) \(previewEntries.count == 1 ? "activity" : "activities")")
                .appFont(.verdictLabel)
                .foregroundStyle(theme.colors.textSecondary)

            HStack(spacing: AppSpacing.sm) {
                Button {
                    rejectPreviews()
                } label: {
                    Label("Reject", systemImage: "xmark")
                        .appFont(.bodyBold)
                        .foregroundStyle(theme.colors.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xs)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)

                Button {
                    acceptPreviews()
                } label: {
                    Label("Accept all", systemImage: "checkmark")
                        .appFont(.bodyBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xs)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.colors.primary)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm + 2)
        .skylineGlass(
            .chrome,
            in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous),
            theme: theme
        )
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.md)
    }

    // MARK: - AI Generation Loading Overlay

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
/// The trip as an object: a photograph with its name on it, then one panel of
/// evidence. Not a centred title over three labelled fields.
struct TripHeaderView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let trip: Trip
    let entries: [TripEntry]

    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 300
    @ScaledMetric(relativeTo: .body) private var dividerHeight: CGFloat = 28

    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                TripHeaderImageView(trip: trip, entries: entries)
                    .frame(height: heroHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    // The map dissolves into the page rather than being cut off
                    // by a hard edge, and the title below can therefore use the
                    // ordinary text tokens in both themes.
                    .overlay { TripImageScrim(start: 0.38) }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(trip.destination.uppercased())
                        .appFont(.verdictLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityHidden(true)

                    Text(trip.title)
                        .appFont(.titleLarge)
                        .foregroundStyle(theme.colors.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(trip.title), \(trip.destination)"))
            }

            statPanel
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)

            if let description = trip.description, !description.isEmpty {
                Text(description)
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
            }
        }
        .padding(.bottom, AppSpacing.lg)
        .background(theme.colors.background)
    }

    // MARK: Stats

    /// Glass, because this is one liftable object sitting on the page. Status
    /// is gone: it duplicated the filter the user came through, and its three
    /// hues were unmanaged system colours that survived neither theme.
    private var statPanel: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: 0) {
            statColumn(label: "Days", value: trip.durationText)
            statDivider
            statColumn(label: "Dates", value: trip.dateRangeText)
            statDivider
            statColumn(label: "Logged", value: entries.isEmpty ? "—" : "\(entries.count)")
        }
        .padding(.vertical, AppSpacing.md)
        .skylineGlassCard(theme: theme)
        .accessibilityElement(children: .contain)
    }

    private func statColumn(label: String, value: String) -> some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.xs) {
            Text(value)
                .appFont(.bodyBold)
                .foregroundStyle(theme.colors.text)

            Text(label.uppercased())
                .appFont(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value)"))
    }

    /// A bare `Divider()` is a semantic separator that follows the DEVICE
    /// appearance. A token-filled rectangle follows the app's theme.
    private var statDivider: some View {
        Rectangle()
            .fill(themeManager.currentTheme.colors.border)
            .frame(width: 1, height: dividerHeight)
            .accessibilityHidden(true)
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

    // A polyline between two consecutive entries. It deliberately carries no
    // colour: the route is stroked in the theme's flight-path tokens at render
    // time, so it re-colours when the user flips the theme instead of freezing
    // whatever the theme happened to be when the route was fetched.
    struct RouteSegment: Identifiable {
        let id = UUID()
        let coordinates: [CLLocationCoordinate2D]
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
        let theme = themeManager.currentTheme

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
                            // The route is one journey, so it gets the one
                            // journey colour the globe already uses, not a
                            // blend of two unmanaged per-entry-type hues.
                            let segmentColor = interpolateColor(
                                from: theme.colors.flightPathStart,
                                to: theme.colors.flightPathEnd,
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
                                color: entry.isPreview ? theme.colors.secondary : theme.colors.primary
                            )
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .mapControlVisibility(.hidden)
            // MapKit renders against the trait colour scheme, i.e. the DEVICE
            // appearance. Pinning it to the app's theme is what stops a
            // light-theme trip screen showing a black map on a dark phone.
            .environment(\.colorScheme, theme.colorScheme)
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
            .overlay(alignment: .bottom) {
                // Never bare text over a live map: a glass capsule gives the
                // label its own backdrop, and Reduce Transparency turns it into
                // an opaque `glassFallback` chip rather than removing it.
                VStack(spacing: AppSpacing.sm) {
                    if isLoadingRoutes && routes.isEmpty {
                        HStack(spacing: AppSpacing.sm) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.text))
                                .scaleEffect(0.8)
                            Text("Loading routes…")
                                .appFont(.verdictLabel)
                        }
                        .foregroundStyle(theme.colors.text)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .skylineGlassCapsule(theme: theme)
                    }

                    HStack(spacing: AppSpacing.xs + 2) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("Tap to expand")
                    }
                    .appFont(.verdictLabel)
                    .foregroundStyle(theme.colors.text)
                    .padding(.horizontal, AppSpacing.sm + 4)
                    .padding(.vertical, AppSpacing.sm - 2)
                    .skylineGlassCapsule(theme: theme)
                }
                .padding(.bottom, AppSpacing.xl + AppSpacing.md)
                .allowsHitTesting(false)
            }
            .sheet(isPresented: $showingExpandedMap) {
                ExpandedMapView(
                    trip: trip,
                    entries: entries,
                    routes: routes,
                    entriesWithLocations: entriesWithLocations
                )
            }
        } else {
            // Fallback for trips without coordinates. Two theme tokens rather
            // than four hardcoded RGB triples ternaried on the theme.
            ZStack {
                LinearGradient(
                    colors: [theme.colors.surface, theme.colors.background],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Image(systemName: "map")
                    .font(AppTypography.mono(.largeTitle))
                    .foregroundStyle(theme.colors.textSecondary.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)
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
            return RouteSegment(coordinates: [])
        }

        // Check cache first
        if let cached = await RouteCache.shared.getRoute(from: startEntry.id, to: endEntry.id) {
            print("✅ Using cached route: \(startEntry.title) → \(endEntry.title)")
            return RouteSegment(coordinates: cached.coordinates.map { $0.coordinate })
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

                return RouteSegment(coordinates: coordinates)
            }
        } catch {
            // Silently fall back to straight line
        }

        // Fallback to straight line (don't cache this)
        return RouteSegment(coordinates: [startCoord, endCoord])
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let groupedByRegion: [(regionName: String, regionOrder: Int, entryCount: Int)]
    @Binding var selectedRegionIndex: Int?
    let onRegionSelected: (Int) -> Void

    private var scrollAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    var body: some View {
        let theme = themeManager.currentTheme

        return ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // One container: adjacent glass chips share a single backdrop
                // instead of stacking blurs.
                SkyLineGlassPanel(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(Array(groupedByRegion.enumerated()), id: \.offset) { index, regionGroup in
                            let isSelected = index == selectedRegionIndex
                            let (regionName, _, entryCount) = regionGroup

                            Button {
                                onRegionSelected(index)
                            } label: {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(AppTypography.mono(.subheadline, weight: .medium))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.textSecondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(regionName)
                                            .appFont(.bodyBold, lineLimit: .exactly(1))
                                            .foregroundStyle(theme.colors.text)

                                        Text("\(entryCount) \(entryCount == 1 ? "activity" : "activities")")
                                            .appFont(.placeMeta)
                                            .foregroundStyle(theme.colors.textSecondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.sm + 2)
                                .frame(minWidth: 180, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .skylineGlassCard(
                                cornerRadius: AppRadius.lg,
                                tint: isSelected ? theme.colors.primary.opacity(0.28) : nil,
                                theme: theme
                            )
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                        .stroke(theme.colors.primary, lineWidth: 1.5)
                                }
                            }
                            .animation(scrollAnimation, value: isSelected)
                            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                            .id("region_selector_\(index)")
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)
            }
            .onChange(of: selectedRegionIndex) { _, newValue in
                if let newValue = newValue {
                    withAnimation(scrollAnimation) {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let groupedEntries: [(Date, [TripEntry])]
    @Binding var selectedDayIndex: Int
    let onDaySelected: (Int) -> Void

    private var scrollAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

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
        let theme = themeManager.currentTheme

        return ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                SkyLineGlassPanel(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(Array(groupedEntries.enumerated()), id: \.offset) { index, dayGroup in
                            let (date, entries) = dayGroup
                            let isSelected = index == selectedDayIndex

                            Button {
                                onDaySelected(index)
                            } label: {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "calendar")
                                        .font(AppTypography.mono(.subheadline, weight: .medium))
                                        .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.textSecondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dayTitle(for: date))
                                            .appFont(.bodyBold, lineLimit: .exactly(1))
                                            .foregroundStyle(theme.colors.text)

                                        Text(dateRange(for: date))
                                            .appFont(.placeMeta)
                                            .foregroundStyle(theme.colors.textSecondary)
                                    }

                                    Spacer(minLength: AppSpacing.sm)

                                    Text("\(entries.count)")
                                        .appFont(.verdictLabel)
                                        .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.textSecondary)
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.sm + 2)
                                .frame(minWidth: 200, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .skylineGlassCard(
                                cornerRadius: AppRadius.lg,
                                tint: isSelected ? theme.colors.primary.opacity(0.28) : nil,
                                theme: theme
                            )
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                        .stroke(theme.colors.primary, lineWidth: 1.5)
                                }
                            }
                            .animation(scrollAnimation, value: isSelected)
                            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                            .id("day_selector_\(index)")
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)
            }
            .onChange(of: selectedDayIndex) { _, newValue in
                withAnimation(scrollAnimation) {
                    scrollProxy.scrollTo("day_selector_\(newValue)", anchor: .center)
                }
            }
        }
    }
}

// MARK: - Region Timeline View
struct RegionTimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let groupedByRegionAndDay: [(regionName: String, regionOrder: Int, days: [(Date, [TripEntry])])]
    @Binding var collapsedRegions: Set<String>
    let timeZone: TimeZone
    let onEntryTap: (TripEntry) -> Void
    let onEntryLongPress: (TripEntry) -> Void
    let onRegionLongPress: (String) -> Void

    private var collapseAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

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
                        withAnimation(collapseAnimation) {
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
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, regionIndex == 0 ? AppSpacing.lg : AppSpacing.xl)
                .padding(.bottom, AppSpacing.md)

                // Days within region (only if not collapsed)
                if !isCollapsed {
                    ForEach(Array(days.enumerated()), id: \.element.0) { dayIndex, dayGroup in
                        let (date, entries) = dayGroup

                        // Day header
                        TimelineDayHeader(date: date, entryCount: entries.count, timeZone: timeZone)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.top, dayIndex == 0 ? 0 : AppSpacing.lg)
                            .padding(.bottom, AppSpacing.sm + 4)

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
                            .padding(.horizontal, AppSpacing.md)
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

            // Clears the floating add button and the tab bar.
            Color.clear
                .frame(height: AppSpacing.xxl + AppSpacing.xl)
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

    private var metaLine: String {
        var parts: [String] = []
        if !dateRange.isEmpty { parts.append(dateRange) }
        parts.append("\(totalDays) \(totalDays == 1 ? "day" : "days")")
        parts.append("\(totalEntries) \(totalEntries == 1 ? "activity" : "activities")")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let theme = themeManager.currentTheme

        return Button {
            onToggle()
        } label: {
            HStack(spacing: AppSpacing.sm + 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(AppTypography.mono(.title3, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.colors.primary)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(regionName)
                        .appFont(.placeName, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.text)

                    // One meta line, not five Text views separated by bullets.
                    Text(metaLine)
                        .appFont(.placeMeta, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Spacer(minLength: AppSpacing.sm)

                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(AppTypography.mono(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(AppSpacing.md)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        // One elevation signal. The material draws its own edge, so there is
        // no stroke and no shadow stacked on top of it.
        .skylineGlassCard(theme: theme)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() }
        )
        .accessibilityLabel(Text("\(regionName), \(metaLine)"))
        .accessibilityHint(Text(isCollapsed ? "Expand region" : "Collapse region"))
        .accessibilityAddTraits(.isHeader)
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
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, dayIndex == 0 ? AppSpacing.lg : AppSpacing.xl)
                    .padding(.bottom, AppSpacing.md)

                // Entries for this day
                ForEach(Array(entries.enumerated()), id: \.element.id) { entryIndex, entry in
                    TimelineEntryView(
                        entry: entry,
                        isLast: entryIndex == entries.count - 1 && dayIndex == groupedEntries.count - 1,
                        timeZone: timeZone,
                        onTap: { onEntryTap(entry) },
                        onLongPress: { onEntryLongPress(entry) }
                    )
                    .padding(.horizontal, AppSpacing.md)
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

            // Clears the floating add button and the tab bar.
            Color.clear
                .frame(height: AppSpacing.xxl + AppSpacing.xl)
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
        let theme = themeManager.currentTheme

        // The section-header convention: small, uppercase, secondary. The
        // entry titles below are what should carry the weight.
        return HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Text(dateText.uppercased())
                .appFont(.verdictLabel)
                .foregroundStyle(theme.colors.textSecondary)

            Text("\(entryCount)")
                .appFont(.footnote)
                .foregroundStyle(theme.colors.textSecondary)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(dateText), \(entryCount) \(entryCount == 1 ? "entry" : "entries")"))
        .accessibilityAddTraits(.isHeader)
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

    @ScaledMetric(relativeTo: .body) private var railWidth: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 11

    var body: some View {
        let theme = themeManager.currentTheme

        return HStack(alignment: .top, spacing: AppSpacing.md) {
            // Timeline line and dot
            VStack(spacing: 0) {
                Circle()
                    .fill(railInk)
                    .frame(width: dotSize, height: dotSize)
                    .padding(.top, AppSpacing.md)

                // Vertical line (if not last)
                if !isLast {
                    Rectangle()
                        .fill(theme.colors.border)
                        .frame(width: 2)
                        .frame(minHeight: 60)
                }
            }
            .frame(width: railWidth)
            .accessibilityHidden(true)

            // Entry content
            TimelineEntryCard(entry: entry, timeZone: timeZone, onTap: onTap, onLongPress: onLongPress)
                .padding(.bottom, isLast ? 0 : AppSpacing.md)
        }
    }

    /// The rail is a route, not a legend. Nine unmanaged system hues used to
    /// live here — none theme-aware, none surviving the light/dark polarity
    /// flip, and all of them competing with the three verdict colours that
    /// actually carry meaning. The entry type is already stated by its emoji
    /// and its uppercase label inside the card.
    private var railInk: Color {
        let theme = themeManager.currentTheme
        return entry.isPreview ? theme.colors.secondary : theme.colors.primary
    }
}

// MARK: - Timeline Entry Card
struct TimelineEntryCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    let entry: TripEntry
    let timeZone: TimeZone
    let onTap: () -> Void
    let onLongPress: () -> Void

    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 60

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = timeZone
        return formatter.string(from: entry.timestamp)
    }

    var body: some View {
        let theme = themeManager.currentTheme
        let cardShape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)

        return VStack(alignment: .leading, spacing: AppSpacing.sm + 4) {
            // Header with type and time
            HStack(spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xs + 2) {
                    Text(entry.entryType.emoji)
                        .appFont(.placeMeta)

                    Text(entry.entryType.displayName.uppercased())
                        .appFont(.footnote, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.textSecondary)
                }

                // "Not real yet" is a single semantic, so it gets a single
                // token: `secondary`. The four-stop purple/blue gradient it
                // replaces was the loudest colour in the app attached to the
                // least important content.
                if entry.isPreview {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                        Text("AI")
                    }
                    .appFont(.footnote)
                    .foregroundStyle(theme.colors.secondary)
                    .padding(.horizontal, AppSpacing.sm - 2)
                    .padding(.vertical, 2)
                    .skylineGlassCapsule(tint: theme.colors.secondary.opacity(0.30), theme: theme)
                    .accessibilityLabel(Text("AI suggestion"))
                }

                Spacer(minLength: AppSpacing.xs)

                Text(timeText)
                    .appFont(.placeMeta, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)
            }

            // Title and content
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(entry.title)
                    .appFont(.bodyBold, lineLimit: .exactly(2))
                    .foregroundStyle(theme.colors.text)

                if !entry.content.isEmpty {
                    Text(entry.content)
                        .appFont(.bodySmall, lineLimit: .exactly(3))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }

            // Location if available
            if !entry.displayLocation.isEmpty {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "location")
                    Text(entry.displayLocation)
                }
                .appFont(.placeMeta, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.textSecondary)
            }

            // Images if available
            if entry.hasImages {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(entry.imageURLs.prefix(3), id: \.self) { imageURL in
                            if let url = URL(string: imageURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: thumbSize, height: thumbSize)
                                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .fill(theme.colors.surface)
                                        .frame(width: thumbSize, height: thumbSize)
                                        .overlay(
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        )
                                }
                            }
                        }

                        if entry.imageURLs.count > 3 {
                            Text("+\(entry.imageURLs.count - 3)")
                                .appFont(.verdictLabel)
                                .foregroundStyle(theme.colors.textSecondary)
                                .frame(width: thumbSize, height: thumbSize)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .fill(theme.colors.surface)
                                )
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .accessibilityHidden(true)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Glass is the elevation. No stroke and no shadow layered on top —
        // the old card stacked fill + corner radius + stroke + shadow, four
        // signals for one edge, and the shadow was invisible on 0x0A0F1C.
        .skylineGlass(.card, in: cardShape, theme: theme)
        .containerShape(cardShape)
        .overlay {
            // A preview is provisional: one hairline ring, one token.
            if entry.isPreview {
                cardShape.stroke(theme.colors.secondary, lineWidth: 1)
            }
        }
        .contentShape(cardShape)
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
    let onAddEntry: () -> Void

    var body: some View {
        TripEmptyStateView(
            systemImage: "timeline.selection",
            title: "Nothing logged yet",
            message: "Add the first activity and this trip gets a timeline you can read back later.",
            actionTitle: "Add first entry",
            action: onAddEntry
        )
    }
}

// MARK: - Placeholder Views

struct EntryDetailView: View {
    let entry: TripEntry
    
    var body: some View {
        Text("Entry Detail View - \(entry.title)")
            .appFont(.title)
    }
}

// MARK: - Add Entry Menu View

/// The one place `background` doubles as an on-colour: it is a near-black in
/// light theme and a near-white in dark, so it clears AA against `primary` in
/// both directions. A literal `.white` here is 2.6:1 on the dark palette's
/// `primary`. A real `onPrimary` token would say this out loud.
struct NumberedMarkerView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let number: Int
    let color: Color

    @ScaledMetric(relativeTo: .caption) private var diameter: CGFloat = 30

    var body: some View {
        let theme = themeManager.currentTheme

        return Text("\(number)")
            .appFont(.verdictLabel)
            .foregroundStyle(theme.colors.background)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(theme.colors.background, lineWidth: 2))
            .shadow(color: theme.colors.scrim, radius: 3, x: 0, y: 1)
            .accessibilityLabel(Text("Stop \(number)"))
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
        let theme = themeManager.currentTheme

        return NavigationStack {
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
                                from: theme.colors.flightPathStart,
                                to: theme.colors.flightPathEnd,
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
                                color: entry.isPreview ? theme.colors.secondary : theme.colors.primary
                            )
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .mapControlVisibility(.visible)
            // Follows the APP's theme, not the device appearance.
            .environment(\.colorScheme, theme.colorScheme)
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
                        HStack(spacing: AppSpacing.sm + 4) {
                            Image(systemName: "location.circle.fill")
                            Text("Navigate")
                        }
                        .appFont(.bodyBold)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.md)
                    }
                    // Glass, not `.ultraThinMaterial` — a material samples the
                    // device colour scheme, so it inverted against the app's
                    // own theme.
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(theme.colors.primary)
                    .accessibilityLabel(Text("Navigate this trip"))

                    Spacer()
                }
                .padding(.bottom, AppSpacing.lg)
            }
            .navigationTitle(trip.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppTypography.mono(.body, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Close map"))
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
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.sm + 4) {
            Image(systemName: "map.fill")
                .font(AppTypography.mono(.subheadline, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Organise by regions?")
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)

                Text("Group activities by where they happened")
                    .appFont(.placeMeta, lineLimit: .exactly(2))
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer(minLength: AppSpacing.sm)

            if isDetecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.primary))
                    .scaleEffect(0.85)
            } else {
                SkyLineGlassPanel(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Button(action: onDismiss) {
                            Text("Not now")
                                .appFont(.verdictLabel)
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.xs + 2)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)

                        Button(action: onDetect) {
                            Text("Detect")
                                .appFont(.verdictLabel)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.xs + 2)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(theme.colors.primary)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .skylineGlassCard(tint: theme.colors.primary.opacity(0.16), theme: theme)
        .accessibilityElement(children: .contain)
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
        let theme = themeManager.currentTheme

        return NavigationStack {
            List {
                // Existing regions
                if !existingRegions.isEmpty {
                    Section {
                        ForEach(Array(existingRegions.enumerated()), id: \.offset) { _, region in
                            Button {
                                moveEntry(to: region.regionName, order: region.regionOrder)
                            } label: {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "mappin.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(theme.colors.primary)

                                    Text(region.regionName)
                                        .appFont(.body)
                                        .foregroundStyle(theme.colors.text)

                                    Spacer()

                                    if entry.regionName == region.regionName {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(theme.colors.primary)
                                    }
                                }
                            }
                            .listRowBackground(theme.colors.surface)
                        }
                    } header: {
                        Text("Existing regions".uppercased())
                            .appFont(.verdictLabel)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                // New region option
                Section {
                    if showNewRegionField {
                        HStack {
                            TextField("Region name", text: $newRegionName)
                                .appFont(.body)
                                .foregroundStyle(theme.colors.text)

                            Button("Add") {
                                let nextOrder = (existingRegions.map { $0.regionOrder }.max() ?? -1) + 1
                                moveEntry(to: newRegionName, order: nextOrder)
                            }
                            .appFont(.bodyBold)
                            .disabled(newRegionName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .foregroundStyle(theme.colors.primary)
                        }
                        .listRowBackground(theme.colors.surface)
                    } else {
                        Button {
                            showNewRegionField = true
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(theme.colors.primary)

                                Text("Create new region")
                                    .appFont(.body)
                                    .foregroundStyle(theme.colors.text)
                            }
                        }
                        .listRowBackground(theme.colors.surface)
                    }
                } header: {
                    Text("New region".uppercased())
                        .appFont(.verdictLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                // Remove from region
                if entry.regionName != nil {
                    Section {
                        Button(role: .destructive) {
                            moveEntry(to: nil, order: nil)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "minus.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                Text("Remove from region")
                                    .appFont(.body)
                            }
                            // `error` rather than `.red`: the palette's error
                            // is tuned per theme, `.red` follows the device.
                            .foregroundStyle(theme.colors.error)
                        }
                        .listRowBackground(theme.colors.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { theme.colors.background.ignoresSafeArea() }
            .navigationTitle("Move to Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .appFont(.bodyBold)
                        .foregroundStyle(theme.colors.primary)
                }
            }
            .overlay {
                if isUpdating {
                    ZStack {
                        theme.colors.scrim.ignoresSafeArea()

                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.text))
                            .padding(AppSpacing.lg)
                            .skylineGlassCard(theme: theme)
                    }
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