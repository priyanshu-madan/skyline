//
//  SimpleContentView.swift
//  SkyLine
//
//  Simplified version to test compilation
//

import SwiftUI

struct SimpleContentView: View {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var flightStore = FlightStore()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Simple Globe Screen
            VStack {
                Text("🌍")
                    .font(AppTypography.titleLarge)
                Text("Globe View")
                    .font(.title)
                    .padding()
                
                Button("Toggle Theme") {
                    themeManager.toggleTheme()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .tabItem {
                Image(systemName: "globe")
                Text("Globe")
            }
            .tag(0)
            
            // Simple Search Screen
            VStack(spacing: 20) {
                Text("🔍")
                    .font(AppTypography.titleLarge)
                Text("Search View")
                    .font(.title)
                
                TextField("Enter flight number", text: .constant(""))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button("Search Flights") {
                    // Search action
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .tabItem {
                Image(systemName: "magnifyingglass")
                Text("Search")
            }
            .tag(1)
            
            // Simple Flights Screen
            VStack(spacing: 20) {
                Text("✈️")
                    .font(AppTypography.titleLarge)
                Text("Flights View")
                    .font(.title)
                
                Text("\(flightStore.flightCount) saved flights")
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(flightStore.flights.prefix(3)) { flight in
                        VStack(alignment: .leading) {
                            Text(flight.flightNumber)
                                .font(.headline)
                            Text("\(flight.departure.code) → \(flight.arrival.code)")
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxHeight: 200)
            }
            .tabItem {
                Image(systemName: "airplane")
                Text("Flights")
            }
            .tag(2)
            
            // Simple Profile Screen
            VStack(spacing: 20) {
                Text("👤")
                    .font(AppTypography.titleLarge)
                Text("Profile View")
                    .font(.title)
                
                VStack(spacing: 10) {
                    Text("Theme: \(themeManager.currentTheme.displayName)")
                    Text("Flights: \(flightStore.flightCount)")
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            }
            .tabItem {
                Image(systemName: "person.circle")
                Text("Profile")
            }
            .tag(3)
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
    }
}

#Preview {
    SimpleContentView()
}