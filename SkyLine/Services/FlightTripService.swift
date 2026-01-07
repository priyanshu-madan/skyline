//
//  FlightTripService.swift
//  SkyLine
//
//  Service for converting flights into trip entries and managing flight-trip relationships
//

import Foundation
import CoreLocation

@MainActor
class FlightTripService: ObservableObject {
    static let shared = FlightTripService()
    
    private let tripStore = TripStore.shared
    private let airportService = AirportService.shared
    
    private init() {}
    
    // MARK: - Flight to Trip Conversion
    
    /// Creates a trip entry from flight data
    func createTripEntryFromFlight(_ flight: Flight, for tripId: String) -> TripEntry {
        let title = "Flight \(flight.flightNumber) - \(flight.departure.code) to \(flight.arrival.code)"
        
        var content = ""
        if let airline = flight.airline {
            content += "Airline: \(airline)\n"
        }
        content += "Departure: \(flight.departure.city) (\(flight.departure.code)) at \(flight.departure.displayTime)\n"
        content += "Arrival: \(flight.arrival.city) (\(flight.arrival.code)) at \(flight.arrival.displayTime)\n"
        
        if let duration = flight.flightDuration {
            content += "Duration: \(duration)\n"
        }
        
        if let gate = flight.departure.gate {
            content += "Gate: \(gate)\n"
        }
        
        if let terminal = flight.departure.terminal {
            content += "Terminal: \(terminal)"
        }
        
        // Use departure airport coordinates for location
        let latitude = flight.departure.latitude
        let longitude = flight.departure.longitude
        let locationName = "\(flight.departure.airport), \(flight.departure.city)"
        
        // Use departure date and time for timestamp
        let timestamp = createFlightTimestamp(from: flight)
        
        return TripEntry(
            tripId: tripId,
            timestamp: timestamp,
            entryType: .flight,
            title: title,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            flightId: flight.id
        )
    }
    
    /// Finds relevant existing trips for a flight based on dates and destinations
    func findRelevantTrips(for flight: Flight) -> [Trip] {
        let flightDate = flight.departureDate ?? flight.date
        let departureCity = flight.departure.city.lowercased()
        let arrivalCity = flight.arrival.city.lowercased()
        
        return tripStore.trips.filter { trip in
            // Check if flight date falls within trip dates (with some buffer)
            let tripStartWithBuffer = Calendar.current.date(byAdding: .day, value: -2, to: trip.startDate) ?? trip.startDate
            let tripEndWithBuffer = Calendar.current.date(byAdding: .day, value: 2, to: trip.endDate) ?? trip.endDate
            
            let isDateMatch = flightDate >= tripStartWithBuffer && flightDate <= tripEndWithBuffer
            
            // Check if destination matches trip destination
            let tripDestination = trip.destination.lowercased()
            let isDestinationMatch = tripDestination.contains(departureCity) || 
                                   tripDestination.contains(arrivalCity) ||
                                   departureCity.contains(tripDestination) ||
                                   arrivalCity.contains(tripDestination)
            
            return isDateMatch || isDestinationMatch
        }
        .sorted { trip1, trip2 in
            // Sort by relevance: active trips first, then by start date proximity
            if trip1.isActive && !trip2.isActive {
                return true
            } else if !trip1.isActive && trip2.isActive {
                return false
            } else {
                let flightDistance1 = abs(trip1.startDate.timeIntervalSince(flightDate))
                let flightDistance2 = abs(trip2.startDate.timeIntervalSince(flightDate))
                return flightDistance1 < flightDistance2
            }
        }
    }
    
    /// Creates a new trip from flight data with smart defaults
    func createTripFromFlight(_ flight: Flight) -> Trip {
        let destination = flight.arrival.city
        let destinationCode = flight.arrival.code
        
        // Default trip duration: start 1 day before flight, end 3 days after
        let flightDate = flight.departureDate ?? flight.date
        let tripStart = Calendar.current.date(byAdding: .day, value: -1, to: flightDate) ?? flightDate
        let tripEnd = Calendar.current.date(byAdding: .day, value: 3, to: flightDate) ?? Calendar.current.date(byAdding: .day, value: 4, to: flightDate) ?? flightDate
        
        let title = "Trip to \(destination)"
        let description = "Travel itinerary including flight \(flight.flightNumber) from \(flight.departure.city) to \(flight.arrival.city)"
        
        return Trip(
            title: title,
            destination: destination,
            destinationCode: destinationCode,
            startDate: tripStart,
            endDate: tripEnd,
            description: description,
            latitude: flight.arrival.latitude,
            longitude: flight.arrival.longitude
        )
    }
    
    /// Adds flight to an existing trip
    func addFlightToTrip(_ flight: Flight, tripId: String) async -> Result<TripEntry, FlightTripError> {
        // Check if flight already exists in this trip
        if await isFlightAlreadyInTrip(flight, tripId: tripId) {
            return .failure(.flightAlreadyExists)
        }
        
        let entry = createTripEntryFromFlight(flight, for: tripId)
        
        let result = await tripStore.addEntry(entry)
        switch result {
        case .success:
            return .success(entry)
        case .failure(let error):
            return .failure(.addEntryFailed(error.localizedDescription))
        }
    }
    
    /// Creates a new trip with the flight as the first entry
    func createTripWithFlight(_ flight: Flight, customTitle: String? = nil, customStartDate: Date? = nil, customEndDate: Date? = nil) async -> Result<(Trip, TripEntry), FlightTripError> {
        var trip = createTripFromFlight(flight)
        
        // Apply custom values if provided
        if let customTitle = customTitle, !customTitle.isEmpty {
            trip = Trip(
                id: trip.id,
                title: customTitle,
                destination: trip.destination,
                destinationCode: trip.destinationCode,
                startDate: customStartDate ?? trip.startDate,
                endDate: customEndDate ?? trip.endDate,
                description: trip.description,
                coverImageURL: trip.coverImageURL,
                latitude: trip.latitude,
                longitude: trip.longitude,
                createdAt: trip.createdAt,
                updatedAt: trip.updatedAt
            )
        }
        
        // First create the trip
        let tripResult = await tripStore.addTrip(trip)
        switch tripResult {
        case .success:
            // Then add the flight entry
            let entryResult = await addFlightToTrip(flight, tripId: trip.id)
            switch entryResult {
            case .success(let entry):
                return .success((trip, entry))
            case .failure(let error):
                // TODO: Consider removing the created trip if entry creation fails
                return .failure(error)
            }
        case .failure(let error):
            return .failure(.createTripFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Helper Methods
    
    /// Creates a proper timestamp by combining flight departure date with departure time
    private func createFlightTimestamp(from flight: Flight) -> Date {
        let departureDate = flight.departureDate ?? flight.date
        
        // Try to parse the departure time and combine it with the date
        if let parsedTime = parseTimeString(flight.departure.time, date: departureDate) {
            return parsedTime
        }
        
        // Fallback to just the departure date
        return departureDate
    }
    
    /// Parses time string and combines with given date
    private func parseTimeString(_ timeString: String, date: Date) -> Date? {
        let timeFormats = ["HH:mm", "H:mm", "h:mm a", "h:mm"]
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        
        for format in timeFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let timeDate = formatter.date(from: timeString) {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
                
                var combinedComponents = DateComponents()
                combinedComponents.year = dateComponents.year
                combinedComponents.month = dateComponents.month
                combinedComponents.day = dateComponents.day
                combinedComponents.hour = timeComponents.hour
                combinedComponents.minute = timeComponents.minute
                
                return calendar.date(from: combinedComponents)
            }
        }
        
        return nil
    }
    
    /// Checks if a flight already exists in a trip
    private func isFlightAlreadyInTrip(_ flight: Flight, tripId: String) async -> Bool {
        let tripEntries = tripStore.getEntries(for: tripId)
        
        // Check for entries with matching flightId
        if tripEntries.contains(where: { $0.flightId == flight.id }) {
            return true
        }
        
        // Also check for entries with similar flight details (for older entries without flightId)
        let flightTitle = "Flight \(flight.flightNumber) - \(flight.departure.code) to \(flight.arrival.code)"
        if tripEntries.contains(where: { $0.entryType == .flight && $0.title == flightTitle }) {
            return true
        }
        
        return false
    }
}

// MARK: - FlightTripError
enum FlightTripError: Error {
    case createTripFailed(String)
    case addEntryFailed(String)
    case tripNotFound
    case invalidFlightData
    case flightAlreadyExists
    
    var localizedDescription: String {
        switch self {
        case .createTripFailed(let message):
            return "Failed to create trip: \(message)"
        case .addEntryFailed(let message):
            return "Failed to add flight entry: \(message)"
        case .tripNotFound:
            return "Trip not found"
        case .invalidFlightData:
            return "Invalid flight data"
        case .flightAlreadyExists:
            return "This flight is already in your trip"
        }
    }
}