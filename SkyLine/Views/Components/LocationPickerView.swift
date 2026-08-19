//
//  LocationPickerView.swift
//  SkyLine
//
//  Interactive map view for selecting travel destinations with a centre crosshair.
//
//  Everything on this screen floats over LIVE map imagery, which has no theme and
//  no predictable luminance. So every piece of chrome here is glass, exactly as the
//  globe overlay is: glass samples what is actually behind it, which is the only
//  treatment that stays legible over a satellite tile, a motorway and a lake.
//

import SwiftUI
import MapKit

struct LocationPickerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var locationManager = SkyLineLocationManager()
    @StateObject private var destinationSearchManager = DestinationSearchManager()

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedLocationName = ""
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var isGettingLocationDetails = false

    @FocusState private var isSearchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var crosshairSize: CGFloat = 40

    let onLocationSelected: (DestinationSuggestion) -> Void

    var body: some View {
        let theme = themeManager.currentTheme

        // NavigationStack, not the deprecated NavigationView: this screen is
        // presented modally and owns its own bar, and NavigationView splits into a
        // sidebar on iPad.
        return NavigationStack {
            ZStack {
                mapLayer

                VStack(spacing: AppSpacing.sm) {
                    searchBar

                    if showingSearch && !destinationSearchManager.searchResults.isEmpty {
                        searchResults
                    }

                    Spacer(minLength: AppSpacing.md)

                    bottomControls
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.primary)
                    .tint(theme.colors.primary)
                }
            }
        }
        .environment(\.colorScheme, theme.colorScheme)
        .onAppear {
            requestLocationPermissionIfNeeded()
        }
        .alert("Location Permission", isPresented: $locationManager.showingLocationPermissionAlert) {
            Button("Settings") {
                locationManager.openLocationSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(locationManager.permissionMessage)
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        let theme = themeManager.currentTheme

        return ZStack {
            Map(position: $cameraPosition) {
                // Show user location if available
                if let userLocation = locationManager.currentLocation {
                    Marker("Your Location", coordinate: userLocation.coordinate)
                        .tint(theme.colors.primary)
                }
            }
            .onMapCameraChange { context in
                // Update selected coordinate as map moves
                selectedCoordinate = context.camera.centerCoordinate
                if !isGettingLocationDetails {
                    getLocationName(for: context.camera.centerCoordinate)
                }
            }
            .mapStyle(.standard)
            .ignoresSafeArea()

            // Centre crosshair. A white disc with a black shadow — what this used to
            // be — disappears against a light map tile in either theme. Glass keeps
            // its edge over whatever the map happens to be showing, and the
            // Reduce Transparency fallback inside `skylineGlass` gives it an opaque
            // themed disc rather than nothing at all.
            Image(systemName: "plus")
                .font(AppTypography.mono(.callout, weight: .bold))
                .foregroundStyle(theme.colors.primary)
                .frame(width: crosshairSize, height: crosshairSize)
                .skylineGlass(.control, in: Circle(), theme: theme)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        let theme = themeManager.currentTheme

        return SkyLineGlassPanel(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(AppTypography.mono(.callout, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityHidden(true)

                TextField("Search destinations…", text: $searchText)
                    .appFont(.body, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)
                    .tint(theme.colors.primary)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onChange(of: searchText) { _, newValue in
                        destinationSearchManager.search(for: newValue)
                        showingSearch = !newValue.isEmpty
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showingSearch {
                    Button("Cancel") {
                        searchText = ""
                        showingSearch = false
                        isSearchFocused = false
                        destinationSearchManager.clearSearch()
                    }
                    .appFont(.verdictLabel, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.primary)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm + 4)
            .skylineGlass(
                .chrome,
                in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous),
                theme: theme
            )
        }
    }

    private var searchResults: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: 0) {
            ForEach(Array(destinationSearchManager.searchResults.prefix(5).enumerated()), id: \.element.title) { index, result in
                Button {
                    selectSearchResult(result)
                } label: {
                    DestinationResultRow(title: result.title, subtitle: result.subtitle)
                }
                .buttonStyle(.plain)

                if index < min(destinationSearchManager.searchResults.count - 1, 4) {
                    Rectangle()
                        .fill(theme.colors.border)
                        .frame(height: 1)
                        .padding(.leading, AppSpacing.md)
                        .accessibilityHidden(true)
                }
            }
        }
        // Opaque here, not glass: this panel sits directly on moving map imagery and
        // holds two lines of small type per row. Glass would let street labels read
        // straight through the place names.
        .formFloatingPanel(theme: theme)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        let theme = themeManager.currentTheme

        return SkyLineGlassPanel(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.sm + 4) {
                if !selectedLocationName.isEmpty {
                    VStack(spacing: AppSpacing.xs) {
                        Text("Selected location".uppercased())
                            .appFont(.verdictLabel, lineLimit: .exactly(1))
                            .foregroundStyle(theme.colors.textSecondary)

                        Text(selectedLocationName)
                            .appFont(.placeName, lineLimit: .exactly(2))
                            .foregroundStyle(theme.colors.text)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }

                FormPrimaryButton(
                    title: "Select Location",
                    systemImage: "checkmark",
                    busyTitle: "Processing…",
                    isBusy: isGettingLocationDetails,
                    isEnabled: selectedCoordinate != nil
                ) {
                    confirmSelection()
                }

                if locationManager.canRequestLocation {
                    FormSecondaryButton(
                        title: locationManager.isLoading ? "Locating…" : "Use Current Location",
                        systemImage: "location.circle.fill"
                    ) {
                        useCurrentLocation()
                    }
                    .disabled(locationManager.isLoading)
                }
            }
            .padding(AppSpacing.md)
            .skylineGlass(
                .chrome,
                in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous),
                theme: theme
            )
        }
    }

    // MARK: - Helper Functions

    private func requestLocationPermissionIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermission()
        }
    }

    private func useCurrentLocation() {
        locationManager.requestLocation()

        if let currentLocation = locationManager.currentLocation {
            selectedCoordinate = currentLocation.coordinate
            cameraPosition = .region(MKCoordinateRegion(
                center: currentLocation.coordinate,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            ))
            getLocationName(for: currentLocation.coordinate)
        }
    }

    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        Task {
            if let destination = await destinationSearchManager.getLocationDetails(for: result) {
                await MainActor.run {
                    selectedCoordinate = CLLocationCoordinate2D(
                        latitude: destination.latitude,
                        longitude: destination.longitude
                    )
                    selectedLocationName = destination.displayName
                    cameraPosition = .region(MKCoordinateRegion(
                        center: selectedCoordinate!,
                        latitudinalMeters: 5000,
                        longitudinalMeters: 5000
                    ))
                    searchText = ""
                    showingSearch = false
                    isSearchFocused = false
                    destinationSearchManager.clearSearch()
                }
            }
        }
    }

    private func getLocationName(for coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    let name = [placemark.locality, placemark.country]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                    selectedLocationName = name.isEmpty ? "Selected Location" : name
                } else {
                    selectedLocationName = "Selected Location"
                }
            }
        }
    }

    private func confirmSelection() {
        guard let coordinate = selectedCoordinate else { return }

        isGettingLocationDetails = true

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                isGettingLocationDetails = false

                if let placemark = placemarks?.first {
                    let city = placemark.locality ?? "Unknown City"
                    let country = placemark.country ?? "Unknown Country"

                    let destination = DestinationSuggestion(
                        city: city,
                        country: country,
                        airportCode: nil, // Could be enhanced to find nearby airport
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )

                    onLocationSelected(destination)
                    dismiss()
                } else {
                    // Fallback if geocoding fails
                    let destination = DestinationSuggestion(
                        city: selectedLocationName.isEmpty ? "Selected Location" : selectedLocationName,
                        country: "",
                        airportCode: nil,
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )

                    onLocationSelected(destination)
                    dismiss()
                }
            }
        }
    }
}
