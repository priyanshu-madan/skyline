//
//  LocationPickerView.swift
//  SkyLine
//
//  Interactive map view for selecting travel destinations with draggable pin
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
    
    let onLocationSelected: (DestinationSuggestion) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map View
                ZStack {
                    Map(position: $cameraPosition) {
                        // Show user location if available
                        if let userLocation = locationManager.currentLocation {
                            Marker("Your Location", coordinate: userLocation.coordinate)
                                .tint(.blue)
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
                    
                    // Center crosshair for pin placement
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 30, height: 30)
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                        )
                }
                
                // Search overlay
                VStack {
                    // Search bar
                    HStack {
                        TextField("Search destinations...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: searchText) { _, newValue in
                                destinationSearchManager.search(for: newValue)
                                showingSearch = !newValue.isEmpty
                            }
                        
                        if showingSearch {
                            Button("Cancel") {
                                searchText = ""
                                showingSearch = false
                                destinationSearchManager.clearSearch()
                            }
                            .foregroundColor(themeManager.currentTheme.colors.primary)
                        }
                    }
                    .padding()
                    .background(themeManager.currentTheme.colors.background.opacity(0.95))
                    
                    // Search results
                    if showingSearch && !destinationSearchManager.searchResults.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(destinationSearchManager.searchResults.prefix(5).enumerated()), id: \.element.title) { index, result in
                                Button {
                                    selectSearchResult(result)
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
                                            .foregroundColor(themeManager.currentTheme.colors.primary)
                                    }
                                    .padding()
                                    .background(themeManager.currentTheme.colors.surface)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if index < min(destinationSearchManager.searchResults.count - 1, 4) {
                                    Divider()
                                }
                            }
                        }
                        .background(themeManager.currentTheme.colors.surface)
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .shadow(color: .black.opacity(0.1), radius: 4)
                    }
                    
                    Spacer()
                    
                    // Bottom controls
                    VStack(spacing: 16) {
                        // Current location info
                        if !selectedLocationName.isEmpty {
                            VStack(spacing: 8) {
                                Text("Selected Location")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    .textCase(.uppercase)
                                
                                Text(selectedLocationName)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(themeManager.currentTheme.colors.text)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .padding()
                            .background(themeManager.currentTheme.colors.surface.opacity(0.95))
                            .cornerRadius(12)
                        }
                        
                        // Action buttons
                        HStack(spacing: 16) {
                            // Use current location button
                            if locationManager.canRequestLocation {
                                Button {
                                    useCurrentLocation()
                                } label: {
                                    HStack {
                                        if locationManager.isLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "location.circle.fill")
                                        }
                                        Text("Current")
                                    }
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(themeManager.currentTheme.colors.primary.opacity(0.8))
                                    .cornerRadius(8)
                                }
                                .disabled(locationManager.isLoading)
                            }
                            
                            // Confirm selection button
                            Button {
                                confirmSelection()
                            } label: {
                                HStack {
                                    if isGettingLocationDetails {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                        Text("Processing...")
                                    } else {
                                        Image(systemName: "checkmark")
                                        Text("Select Location")
                                    }
                                }
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(selectedCoordinate != nil ? themeManager.currentTheme.colors.primary : Color.gray)
                                .cornerRadius(8)
                            }
                            .disabled(selectedCoordinate == nil || isGettingLocationDetails)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
        }
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