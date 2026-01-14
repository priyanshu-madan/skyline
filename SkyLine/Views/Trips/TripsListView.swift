//
//  TripsListView.swift
//  SkyLine
//
//  Main trips listing view for the travel journal
//

import SwiftUI
import MapKit

struct TripsListView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var tripStore = TripStore.shared
    @State private var showingAddTrip = false
    @State private var selectedTrip: Trip?
    
    let onFlightSelected: ((Flight, Trip) -> Void)?
    let externalTripSelection: Trip?
    
    init(onFlightSelected: ((Flight, Trip) -> Void)? = nil, externalTripSelection: Trip? = nil) {
        self.onFlightSelected = onFlightSelected
        self.externalTripSelection = externalTripSelection
    }
    
    var body: some View {
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
                    onTripSelected: { trip in
                        selectedTrip = trip
                    }
                )
            }
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

// MARK: - Empty State
struct EmptyTripsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let onAddTrip: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "suitcase")
                    .font(.system(size: 64, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                    .animation(.easeInOut(duration: 0.3), value: themeManager.currentTheme)
                
                Text("Start Your Journey")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("Document your travels and create beautiful memories with photos and stories")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button {
                    onAddTrip()
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Your First Trip")
                    }
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.currentTheme.colors.primary)
                    .cornerRadius(8)
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trips Content
struct TripsContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var tripStore: TripStore
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
        LazyVStack(spacing: 24) {
            // Show subtle loading indicator when refreshing
            if tripStore.isLoading && !tripStore.trips.isEmpty {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                        .scaleEffect(0.8)
                    
                    Text("Syncing...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                .padding(.top, 8)
            }
            
            // Active/Upcoming Trips
            if !tripStore.activeTrips.isEmpty || !tripStore.upcomingTrips.isEmpty {
                VStack(spacing: 16) {
                    if !tripStore.activeTrips.isEmpty {
                        TripSectionView(
                            title: "Active Trips",
                            trips: tripStore.activeTrips,
                            onTripSelected: onTripSelected,
                            onTripDeleted: deleteTrip,
                            deletingTripId: deletingTripId
                        )
                    }
                    
                    if !tripStore.upcomingTrips.isEmpty {
                        TripSectionView(
                            title: "Upcoming Trips",
                            trips: tripStore.upcomingTrips,
                            onTripSelected: onTripSelected,
                            onTripDeleted: deleteTrip,
                            deletingTripId: deletingTripId
                        )
                    }
                }
            }
            
            // Completed Trips
            if !tripStore.completedTrips.isEmpty {
                TripSectionView(
                    title: "Past Adventures",
                    trips: tripStore.completedTrips,
                    onTripSelected: onTripSelected,
                    onTripDeleted: deleteTrip,
                    deletingTripId: deletingTripId
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Spacer()
                
                Text("\(trips.count)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeManager.currentTheme.colors.surface)
                    .cornerRadius(6)
            }
            
            LazyVStack(spacing: 12) {
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
struct TripCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let trip: Trip
    let onTap: () -> Void
    let onDelete: (Trip) -> Void
    let isDeleting: Bool
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Trip image or placeholder
            TripImageView(trip: trip)
                .frame(height: 140)
                .clipped()
            
            // Trip info
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.title)
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                        .lineLimit(1)
                    
                    Text(trip.destination)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duration")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        
                        Text(trip.durationText)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Status")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            
                            Text(trip.statusText)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(themeManager.currentTheme.colors.text)
                        }
                    }
                }
                
                Text(trip.dateRangeText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            .padding(16)
        }
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(0.05),
            radius: 8,
            x: 0,
            y: 2
        )
        .overlay(
            // Deleting overlay
            Group {
                if isDeleting {
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                                
                                Text("Deleting...")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.white)
                                    .fontWeight(.medium)
                            }
                        )
                        .cornerRadius(16)
                }
            }
        )
        .onTapGesture {
            if !isDeleting {
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

// MARK: - Trip Image View
struct TripImageView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let trip: Trip

    var body: some View {
        if let latitude = trip.latitude, let longitude = trip.longitude {
            // Show map preview for trips with coordinates
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )

            Map(initialPosition: .region(region)) {
                Marker(trip.destination, coordinate: coordinate)
                    .tint(.red)
            }
            .mapStyle(.standard)
            .mapControlVisibility(.hidden)
            .allowsHitTesting(false)
            .cornerRadius(16, corners: [.topLeft, .topRight])
            .id("\(latitude),\(longitude)")  // Force update when coordinates change
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

                // Fallback icon and destination name
                VStack(spacing: 8) {
                    Image(systemName: "building.2")
                        .font(.system(size: 32, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)

                    Text(trip.destination)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
            }
            .cornerRadius(16, corners: [.topLeft, .topRight])
        }
    }
}

// MARK: - Corner Radius Extension
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

// MARK: - Loading State
struct LoadingTripsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                    .scaleEffect(1.2)
                
                Text("Loading Your Trips...")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("Syncing from iCloud")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Placeholder Views

#Preview {
    TripsListView()
        .environmentObject(ThemeManager())
}