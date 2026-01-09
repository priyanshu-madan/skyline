//
//  LocationManager.swift
//  SkyLine
//
//  Location management service for getting current user location
//

import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
class SkyLineLocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingLocationPermissionAlert = false
    @Published var permissionDeniedPermanently = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }
    
    func requestLocation() {
        guard authorizationStatus != .denied else {
            errorMessage = "Location access denied. Please enable in Settings."
            return
        }
        
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            isLoading = true
            errorMessage = nil
            locationManager.requestLocation()
        }
    }
    
    func requestPermission() {
        if authorizationStatus == .denied {
            // Show alert to go to Settings
            showingLocationPermissionAlert = true
            permissionDeniedPermanently = true
            return
        }
        locationManager.requestWhenInUseAuthorization()
    }
    
    func openLocationSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    var permissionMessage: String {
        switch authorizationStatus {
        case .denied, .restricted:
            return "Location access is required to help you discover destinations and provide personalized travel suggestions. Please enable location access in Settings."
        case .notDetermined:
            return "Allow SkyLine to access your location to discover nearby destinations and provide better travel suggestions."
        case .authorizedWhenInUse, .authorizedAlways:
            return "Location access granted"
        @unknown default:
            return "Location permission status unknown"
        }
    }
    
    var canRequestLocation: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
    private func handleLocationUpdate(_ location: CLLocation) {
        currentLocation = location
        isLoading = false
        errorMessage = nil
    }
    
    private func handleLocationError(_ error: Error) {
        isLoading = false
        errorMessage = "Failed to get location: \(error.localizedDescription)"
        print("❌ Location error: \(error)")
    }
}

// MARK: - CLLocationManagerDelegate
extension SkyLineLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            handleLocationUpdate(location)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            handleLocationError(error)
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            
            switch authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                // Permission granted, clear any error messages
                errorMessage = nil
                permissionDeniedPermanently = false
                showingLocationPermissionAlert = false
            case .denied:
                permissionDeniedPermanently = true
                errorMessage = "Location access denied. Enable in Settings to discover destinations."
            case .restricted:
                errorMessage = "Location access restricted. Check device restrictions."
            case .notDetermined:
                permissionDeniedPermanently = false
                errorMessage = nil
            @unknown default:
                errorMessage = "Unknown location permission status"
            }
        }
    }
}