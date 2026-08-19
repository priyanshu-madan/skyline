//
//  TripsListView.swift
//  SkyLine
//
//  The trips tab. A trip is an object you open — a photograph with a name on
//  it — not a database record with four labelled fields.
//
//  Every colour here comes from `themeManager.currentTheme.colors` or a
//  `Verdict` token. Nothing resolves against the DEVICE appearance, which is
//  what used to make the app's Light theme render dark cards on a dark phone.
//

import SwiftUI
import MapKit

enum TripFilter: String, CaseIterable {
    case active = "Active"
    case upcoming = "Upcoming"
    case past = "Past"
}

struct TripsListView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var tripStore = TripStore.shared
    @State private var showingAddTrip = false
    @State private var selectedTrip: Trip?
    @State private var selectedFilter: TripFilter = .active

    let onFlightSelected: ((Flight, Trip) -> Void)?
    let externalTripSelection: Trip?

    init(onFlightSelected: ((Flight, Trip) -> Void)? = nil, externalTripSelection: Trip? = nil) {
        self.onFlightSelected = onFlightSelected
        self.externalTripSelection = externalTripSelection
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented Control
            if !tripStore.trips.isEmpty {
                TripFilterSegmentedControl(selectedFilter: $selectedFilter)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.sm)
            }

            ScrollView {
                if tripStore.isLoading && tripStore.trips.isEmpty {
                    // Show loading state when initially loading and no trips cached
                    LoadingTripsView()
                } else if tripStore.trips.isEmpty && !tripStore.isLoading {
                    // Only show empty state when not loading and truly empty
                    EmptyTripsView(onAddTrip: { showingAddTrip = true })
                } else {
                    TripsContentView(
                        tripStore: tripStore,
                        selectedFilter: selectedFilter,
                        onTripSelected: { trip in
                            selectedTrip = trip
                        }
                    )
                }
            }
            // Content fades under the floating tab bar instead of colliding
            // with it. `.soft` rather than `.hard`: over the live globe a hard
            // edge reads as a seam.
            .skylineScrollEdges()
        }
        .refreshable {
            await tripStore.forceSync()
        }
        .sheet(isPresented: $showingAddTrip) {
            AddTripView()
                .environmentObject(themeManager)
                .environmentObject(tripStore)
        }
        .sheet(item: $selectedTrip) { trip in
            TripDetailView(trip: trip, onFlightSelected: onFlightSelected)
                .environmentObject(themeManager)
                .environmentObject(tripStore)
        }
        .onAppear {
            // Handle external trip selection
            if let externalTrip = externalTripSelection {
                selectedTrip = externalTrip
            }
        }
        .onChange(of: externalTripSelection) { _, newTrip in
            if let trip = newTrip {
                selectedTrip = trip
            }
        }
    }
}

// MARK: - Photo Scrim
/// A photograph, a map tile or a placeholder has no theme of its own. Rather
/// than laying absolute black over it and writing in absolute white — which
/// gives one hardcoded pair that only suits dark mode — the image dissolves
/// into the page colour at its bottom edge, so the caption over it can use the
/// ordinary `text` / `textSecondary` tokens and stays legible in both themes.
struct TripImageScrim: View {
    @EnvironmentObject var themeManager: ThemeManager

    /// Where the fade starts. Lower = more of the image is veiled.
    var start: CGFloat = 0.30

    var body: some View {
        let base = themeManager.currentTheme.colors.background
        LinearGradient(
            stops: [
                .init(color: .clear, location: start),
                .init(color: base.opacity(0.55), location: (start + 1.0) / 2),
                .init(color: base.opacity(0.97), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Empty State
/// Thin wrapper so the existing call site keeps its name. The layout, copy and
/// accent all live in `PlaceLogEmptyState`, which is the one empty state in the
/// app.
struct EmptyTripsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let onAddTrip: () -> Void

    var body: some View {
        PlaceLogEmptyStateView(state: .noTrips, onPrimaryAction: onAddTrip)
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.xl)
    }
}

// MARK: - Trip Empty State
/// One shared empty state for the trip surfaces that `PlaceLogEmptyState` has
/// no case for yet (filtered lists, an empty timeline). Same grammar as
/// `PlaceLogEmptyStateView` deliberately — glyph in a tinted glass well, title,
/// message, optional glass-prominent action.
struct TripEmptyStateView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let systemImage: String
    let title: String
    let message: String
    var accent: Color? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var glyphWell: CGFloat = 76

    var body: some View {
        let theme = themeManager.currentTheme
        let ink = accent ?? theme.colors.textSecondary

        return VStack(spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .regular, design: .monospaced))
                .foregroundStyle(ink)
                .symbolRenderingMode(.hierarchical)
                .frame(width: glyphWell, height: glyphWell)
                .skylineGlass(.card, in: Circle(), tint: ink.opacity(0.22), theme: theme)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .appFont(.headline)
                    .foregroundStyle(theme.colors.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if let actionTitle, let action {
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    action()
                } label: {
                    Text(actionTitle)
                        .appFont(.bodyBold)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.xs)
                }
                // `.glassProminent` picks its own label colour against the tint.
                // A hand-written `.white` on `colors.primary` is 2.6:1 in dark
                // theme, which is the single worst contrast bug in the app.
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.colors.primary)
                .padding(.top, AppSpacing.xs)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Segmented Control
struct TripFilterSegmentedControl: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedFilter: TripFilter

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 38

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    var body: some View {
        let theme = themeManager.currentTheme

        // One container, so the three capsules sample a single backdrop
        // instead of stacking three separate blurs over the globe.
        return SkyLineGlassPanel(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(TripFilter.allCases, id: \.self) { filter in
                    let isSelected = selectedFilter == filter

                    Button {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        withAnimation(selectionAnimation) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue.uppercased())
                            .appFont(.verdictLabel)
                            .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: minHeight)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .skylineGlassCapsule(
                        tint: isSelected ? theme.colors.primary.opacity(0.32) : nil,
                        interactive: true,
                        theme: theme
                    )
                    .overlay {
                        // Second, colour-independent selection cue.
                        if isSelected {
                            Capsule().stroke(theme.colors.primary, lineWidth: 1.5)
                        }
                    }
                    .animation(selectionAnimation, value: isSelected)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filter trips"))
    }
}

// MARK: - Trips Content
struct TripsContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var tripStore: TripStore
    let selectedFilter: TripFilter
    let onTripSelected: (Trip) -> Void

    @State private var deletingTripId: String?
    
    private func deleteTrip(_ trip: Trip) {
        deletingTripId = trip.id
        Task {
            let result = await tripStore.deleteTrip(trip.id)
            await MainActor.run {
                deletingTripId = nil
                switch result {
                case .success:
                    // Deletion successful - UI will update automatically via @Published
                    break
                case .failure(let error):
                    print("Failed to delete trip: \(error)")
                    // Could show an error alert here if needed
                }
            }
        }
    }
    
    var body: some View {
        LazyVStack(spacing: AppSpacing.lg) {
            // Show subtle loading indicator when refreshing
            if tripStore.isLoading && !tripStore.trips.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                        .scaleEffect(0.8)

                    Text("Syncing…")
                        .appFont(.placeMeta)
                        .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .skylineGlassCapsule(theme: themeManager.currentTheme)
                .padding(.top, AppSpacing.sm)
            }

            switch selectedFilter {
            case .active:
                // Active Trips
                if !tripStore.activeTrips.isEmpty {
                    TripSectionView(
                        title: "Active Trips",
                        trips: tripStore.activeTrips,
                        onTripSelected: onTripSelected,
                        onTripDeleted: deleteTrip,
                        deletingTripId: deletingTripId
                    )
                } else {
                    EmptyFilterStateView(filterType: "active")
                }

            case .upcoming:
                // Upcoming Trips
                if !tripStore.upcomingTrips.isEmpty {
                    TripSectionView(
                        title: "Upcoming Trips",
                        trips: tripStore.upcomingTrips,
                        onTripSelected: onTripSelected,
                        onTripDeleted: deleteTrip,
                        deletingTripId: deletingTripId
                    )
                } else {
                    EmptyFilterStateView(filterType: "upcoming")
                }

            case .past:
                // Past Trips
                if !tripStore.completedTrips.isEmpty {
                    TripSectionView(
                        title: "Past Adventures",
                        trips: tripStore.completedTrips,
                        onTripSelected: onTripSelected,
                        onTripDeleted: deleteTrip,
                        deletingTripId: deletingTripId
                    )
                } else {
                    EmptyFilterStateView(filterType: "past")
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        // Clears the floating tab bar.
        .padding(.bottom, AppSpacing.xxl)
    }
}

// MARK: - Trip Section
struct TripSectionView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    let trips: [Trip]
    let onTripSelected: (Trip) -> Void
    let onTripDeleted: (Trip) -> Void
    let deletingTripId: String?
    
    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section headers are metadata, not titles: small, uppercase,
            // secondary. The trip names are what should carry weight.
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(title.uppercased())
                    .appFont(.verdictLabel)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                Text("\(trips.count)")
                    .appFont(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer()
            }

            LazyVStack(spacing: AppSpacing.md) {
                ForEach(trips) { trip in
                    TripCard(
                        trip: trip,
                        onTap: {
                            onTripSelected(trip)
                        },
                        onDelete: { trip in
                            onTripDeleted(trip)
                        },
                        isDeleting: deletingTripId == trip.id
                    )
                }
            }
        }
    }
}

// MARK: - Trip Card
/// Photography-forward: the map snapshot is the trip's identity and the title
/// sits on it. One metadata line, plus the verdict tallies — the only place
/// colour is allowed to be loud.
struct TripCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    /// Read directly off the singleton rather than the environment so a
    /// missing injection can never crash a row.
    @ObservedObject private var placeStore = PlaceStore.shared

    let trip: Trip
    let onTap: () -> Void
    let onDelete: (Trip) -> Void
    let isDeleting: Bool

    @State private var showingDeleteConfirmation = false

    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 176

    private var verdictCounts: [Verdict: Int] {
        placeStore.places(forTrip: trip.id).reduce(into: [:]) { totals, summary in
            guard let verdict = summary.verdict else { return }
            totals[verdict, default: 0] += 1
        }
    }

    private var placeCount: Int {
        placeStore.places(forTrip: trip.id).count
    }

    var body: some View {
        let theme = themeManager.currentTheme
        let cardShape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                TripImageView(trip: trip)
                    .frame(height: heroHeight)
                    .frame(maxWidth: .infinity)
                    // A concentric child keeps its curvature in step with the
                    // card's instead of guessing a smaller radius.
                    .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
                    .overlay { TripImageScrim() }

                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.title)
                        .appFont(.placeName, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.text)

                    Text(trip.destination)
                        .appFont(.placeMeta, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.md - 4)
                .padding(.bottom, AppSpacing.sm + 2)
            }

            metaRow
                .padding(.horizontal, AppSpacing.md - 4)
                .padding(.top, AppSpacing.sm + 2)
                .padding(.bottom, AppSpacing.sm)
        }
        .padding(AppSpacing.xs)
        // Glass is the card. `surface` on `background` is a ≤2% luminance step
        // in both palettes and cannot carry an edge on its own; the material
        // shifts relative to whatever is behind it, so it works in both.
        // One elevation signal — no stroke, no shadow on top of it.
        .skylineGlassCard(theme: theme)
        .containerShape(cardShape)
        .overlay {
            if isDeleting {
                ZStack {
                    cardShape.fill(theme.colors.scrim)

                    HStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.text))

                        Text("Deleting…")
                            .appFont(.verdictLabel)
                            .foregroundStyle(theme.colors.text)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .skylineGlassCapsule(theme: theme)
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(cardShape)
        .onTapGesture {
            if !isDeleting {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onTap()
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isDeleting {
                showingDeleteConfirmation = true
            }
        }
        .confirmationDialog("Delete Trip", isPresented: $showingDeleteConfirmation) {
            Button("Delete Trip", role: .destructive) {
                onDelete(trip)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \"\(trip.title)\"? This action cannot be undone.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Meta

    /// One line, not four labelled fields. Status is deliberately absent — the
    /// filter above the list and the section header already say it, and a
    /// coloured dot with a word beside it was the lowest information density
    /// on the screen.
    private var metaRow: some View {
        let theme = themeManager.currentTheme
        let counts = verdictCounts

        return HStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs + 1) {
                Text(trip.dateRangeText)
                Text("·")
                Text(trip.durationText)
                if placeCount > 0 {
                    Text("·")
                    Text(placeCount == 1 ? "1 place" : "\(placeCount) places")
                }
            }
            .appFont(.placeMeta, lineLimit: .exactly(1))
            .foregroundStyle(theme.colors.textSecondary)

            Spacer(minLength: AppSpacing.sm)

            // Verdicts are the only saturated colour on this screen. Icon
            // silhouettes differ too, so the tally survives greyscale.
            if !counts.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(Verdict.allCases) { verdict in
                        if let count = counts[verdict], count > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: verdict.systemImage)
                                    .symbolRenderingMode(.hierarchical)
                                Text("\(count)")
                            }
                            .appFont(.verdictLabel)
                            .foregroundStyle(verdict.color(for: theme))
                        }
                    }
                }
            }
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = [trip.title, trip.destination, trip.dateRangeText, trip.durationText]
        if placeCount > 0 {
            parts.append(placeCount == 1 ? "1 place logged" : "\(placeCount) places logged")
        }
        for verdict in Verdict.allCases {
            if let count = verdictCounts[verdict], count > 0 {
                parts.append("\(count) \(verdict.displayName)")
            }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Trip Image View
/// The trip's photograph. Clipping is the caller's job so the image can nest
/// concentrically inside whatever card is hosting it.
struct TripImageView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let trip: Trip

    var body: some View {
        let theme = themeManager.currentTheme

        if let latitude = trip.latitude, let longitude = trip.longitude {
            // Show map preview for trips with coordinates
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )

            Map(initialPosition: .region(region)) {
                Marker(trip.destination, coordinate: coordinate)
                    .tint(theme.colors.primary)
            }
            .mapStyle(.standard)
            .mapControlVisibility(.hidden)
            .allowsHitTesting(false)
            // MapKit renders against the trait colour scheme, which is the
            // DEVICE appearance. Pin it to the app's theme, or a light-theme
            // app on a dark phone shows a black map inside a white card.
            .environment(\.colorScheme, theme.colorScheme)
            .id("\(latitude),\(longitude)")  // Force update when coordinates change
        } else {
            // Fallback for trips without coordinates
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
}

// MARK: - Corner Radius Extension
// DEPRECATED. `UnevenRoundedRectangle` and `ConcentricRectangle` cover every
// case this used to, and `.cornerRadius(_:)` clips before the shadow so it
// eats the elevation. Kept only because `AddTripView.swift:577` still calls it;
// delete both once that call site is converted.
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Empty Filter State
struct EmptyFilterStateView: View {
    let filterType: String

    var body: some View {
        TripEmptyStateView(
            systemImage: iconName,
            title: emptyTitle,
            message: emptyMessage
        )
    }

    private var iconName: String {
        switch filterType {
        case "active": return "airplane.departure"
        case "upcoming": return "calendar"
        default: return "clock.arrow.circlepath"
        }
    }

    private var emptyTitle: String {
        switch filterType {
        case "active": return "No Active Trips"
        case "upcoming": return "No Upcoming Trips"
        default: return "No Past Trips"
        }
    }

    private var emptyMessage: String {
        switch filterType {
        case "active": return "Your ongoing adventures will appear here"
        case "upcoming": return "Your upcoming adventures will appear here"
        default: return "Your completed trips will appear here"
        }
    }
}

// MARK: - Loading State
struct LoadingTripsView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.primary))
                .scaleEffect(1.2)

            Text("Loading your trips…")
                .appFont(.bodyBold)
                .foregroundStyle(theme.colors.text)

            Text("Syncing from iCloud")
                .appFont(.placeMeta)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Placeholder Views

#Preview {
    TripsListView()
        .environmentObject(ThemeManager())
}
