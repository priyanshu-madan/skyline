//
//  DestinationImageView.swift
//  SkyLine
//
//  SwiftUI component for displaying destination images with loading states
//

import SwiftUI

struct DestinationImageView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var imageService = DestinationImageService.shared
    
    let airportCode: String
    let cityName: String
    let fallbackIcon: String
    
    @State private var destinationImage: UIImage?
    @State private var isLoading: Bool = false
    
    init(airportCode: String, cityName: String, fallbackIcon: String = "airplane") {
        self.airportCode = airportCode
        self.cityName = cityName
        self.fallbackIcon = fallbackIcon
    }
    
    var body: some View {
        Group {
            if let image = destinationImage {
                // Show the destination image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else if isLoading {
                // Show loading state
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: themeManager.currentTheme == .dark ? [
                                Color(red: 0.31, green: 0.31, blue: 0.31),  // dark:from-gray-800
                                Color(red: 0.11, green: 0.11, blue: 0.15)   // dark:to-gray-900
                            ] : [
                                Color(red: 0.98, green: 0.98, blue: 0.98),  // from-gray-50
                                Color.white                                  // to-white
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                            .scaleEffect(0.8)
                        
                        Text("Loading...")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }
            } else {
                // Show fallback placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: themeManager.currentTheme == .dark ? [
                            Color(red: 0.31, green: 0.31, blue: 0.31),  // dark:from-gray-800
                            Color(red: 0.11, green: 0.11, blue: 0.15)   // dark:to-gray-900
                        ] : [
                            Color(red: 0.98, green: 0.98, blue: 0.98),  // from-gray-50
                            Color.white                                  // to-white
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: fallbackIcon)
                                .font(.system(size: 32, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            
                            Text(cityName.isEmpty ? airportCode : cityName)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    )
            }
        }
        .onAppear {
            loadDestinationImage()
        }
        .onChange(of: airportCode) { _, _ in
            loadDestinationImage()
        }
        .onChange(of: cityName) { _, _ in
            loadDestinationImage()
        }
    }
    
    private func loadDestinationImage() {
        // Don't reload if we already have an image for this destination
        if destinationImage != nil && !airportCode.isEmpty {
            return
        }
        
        guard !airportCode.isEmpty || !cityName.isEmpty else {
            return
        }
        
        isLoading = true
        
        Task {
            let image = await imageService.getDestinationImage(
                airportCode: airportCode,
                cityName: cityName
            )
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.destinationImage = image
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Preset Destination Image Views

struct ArrivalDestinationImageView: View {
    let flight: Flight
    
    var body: some View {
        DestinationImageView(
            airportCode: flight.arrival.code,
            cityName: flight.arrival.city,
            fallbackIcon: "airplane.arrival"
        )
    }
}

struct DepartureDestinationImageView: View {
    let flight: Flight
    
    var body: some View {
        DestinationImageView(
            airportCode: flight.departure.code,
            cityName: flight.departure.city,
            fallbackIcon: "airplane.departure"
        )
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        DestinationImageView(
            airportCode: "LAX",
            cityName: "Los Angeles",
            fallbackIcon: "airplane"
        )
        .frame(height: 180)
        .cornerRadius(12)
        
        DestinationImageView(
            airportCode: "JFK",
            cityName: "New York",
            fallbackIcon: "building.2"
        )
        .frame(height: 180)
        .cornerRadius(12)
    }
    .padding()
    .environmentObject(ThemeManager())
}