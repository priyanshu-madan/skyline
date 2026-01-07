//
//  LocationManager.swift
//  SkyLine
//
//  Location management service for getting current user location
//

import Foundation
import CoreLocation
import Combine

@MainActor
class SkyLineLocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var errorMessage: String?
    
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
        locationManager.requestWhenInUseAuthorization()
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
                // Permission granted, can request location
                break
            case .denied, .restricted:
                errorMessage = "Location access denied"
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}