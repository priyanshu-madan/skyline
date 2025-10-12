//
//  PhotoImportView.swift
//  SkyLine
//
//  Photo import view for boarding pass OCR (iOS 15 compatible)
//

import SwiftUI

struct PhotoImportView: View {
    @Environment(\.dismiss) var dismiss
    let onFlightExtracted: (Flight) -> Void
    
    @State private var isProcessing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                // Camera icon
                Image(systemName: "camera.fill")
                    .font(.system(size: 80, design: .monospaced))
                    .foregroundColor(.blue)
                
                VStack(spacing: 16) {
                    Text("Import Boarding Pass")
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                    
                    Text("Take a photo of your boarding pass to automatically import flight details")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 16) {
                    // Mock photo capture button
                    Button(action: {
                        simulatePhotoCapture()
                    }) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Processing...")
                            } else {
                                Image(systemName: "camera")
                                Text("Take Photo")
                            }
                        }
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(isProcessing)
                    
                    // Mock gallery button
                    Button(action: {
                        simulatePhotoSelection()
                    }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Gallery")
                        }
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .disabled(isProcessing)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Import Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func simulatePhotoCapture() {
        isProcessing = true
        
        // Simulate processing delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isProcessing = false
            
            // Create mock extracted flight
            let mockFlight = createMockExtractedFlight()
            onFlightExtracted(mockFlight)
            dismiss()
        }
    }
    
    private func simulatePhotoSelection() {
        isProcessing = true
        
        // Simulate processing delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isProcessing = false
            
            // Create mock extracted flight
            let mockFlight = createMockExtractedFlight()
            onFlightExtracted(mockFlight)
            dismiss()
        }
    }
    
    private func createMockExtractedFlight() -> Flight {
        // Generate a random mock flight
        let flightNumbers = ["UA789", "AA456", "DL123", "WN987", "B6234"]
        let airlines = ["United Airlines", "American Airlines", "Delta Air Lines", "Southwest Airlines", "JetBlue Airways"]
        
        let randomIndex = Int.random(in: 0..<flightNumbers.count)
        
        return Flight(
            id: "ocr-extracted-\(UUID().uuidString)",
            flightNumber: flightNumbers[randomIndex],
            airline: airlines[randomIndex],
            departure: Airport(
                airport: "San Francisco International Airport",
                code: "SFO",
                city: "San Francisco",
                latitude: 37.6213,
                longitude: -122.3790,
                time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(7200)),
                actualTime: nil,
                terminal: "3",
                gate: "G\(Int.random(in: 1...50))",
                delay: nil
            ),
            arrival: Airport(
                airport: "John F. Kennedy International Airport",
                code: "JFK",
                city: "New York",
                latitude: 40.6413,
                longitude: -73.7781,
                time: ISO8601DateFormatter().string(from: Date().addingTimeInterval(25200)),
                actualTime: nil,
                terminal: "4",
                gate: "B\(Int.random(in: 1...30))",
                delay: nil
            ),
            status: .boarding,
            aircraft: Aircraft(
                type: "Boeing 737-800",
                registration: "N\(Int.random(in: 100...999))UA",
                icao24: nil
            ),
            currentPosition: nil,
            progress: 0.0,
            flightDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(7200)),
            dataSource: .pkpass,
            date: Flight.extractFlightDate(from: ISO8601DateFormatter().string(from: Date().addingTimeInterval(7200)))
        )
    }
}

#Preview {
    PhotoImportView { flight in
        print("Extracted flight: \(flight.flightNumber)")
    }
}