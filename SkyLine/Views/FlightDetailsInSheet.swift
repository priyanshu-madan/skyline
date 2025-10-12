//
//  FlightDetailsInSheet.swift
//  SkyLine
//
//  Flight details view displayed within the bottom sheet - Figma design implementation
//

import SwiftUI

struct FlightDetailsInSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    let flight: Flight
    let onClose: () -> Void
    
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    // Aircraft Information Card
                    AircraftInfoCard(flight: flight)
                    
                    // Flight Timeline Card
                    FlightTimelineCard(flight: flight)
                } header: {
                    // Flight Header Section - pinned at top
                    FlightHeaderSection(flight: flight, onClose: onClose)
                        .background(themeManager.currentTheme.colors.background)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(themeManager.currentTheme.colors.background)
        .background(
            ScrollViewOffsetSetter()
        )
        .onAppear {
            print("🔍 DEBUG: FlightDetailsInSheet appeared")
        }
    }
}

struct ScrollViewOffsetSetter: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        DispatchQueue.main.async {
            // Find the ScrollView in the view hierarchy and reset its offset
            if let scrollView = view.findScrollViewParent() {
                print("🔍 DEBUG: Found ScrollView - resetting contentOffset to zero")
                scrollView.setContentOffset(.zero, animated: false)
            } else {
                print("🔍 DEBUG: No ScrollView found in hierarchy")
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Also reset on updates
        DispatchQueue.main.async {
            if let scrollView = uiView.findScrollViewParent() {
                print("🔍 DEBUG: Update - resetting ScrollView contentOffset")
                scrollView.setContentOffset(.zero, animated: false)
            }
        }
    }
}

extension UIView {
    func findScrollViewParent() -> UIScrollView? {
        var currentView: UIView? = self
        while let view = currentView {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            currentView = view.superview
        }
        return nil
    }
}

// MARK: - Flight Header Section
struct FlightHeaderSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    let flight: Flight
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Airline logo placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(flight.airline?.prefix(2).uppercased() ?? "FL")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(DateFormatter.flightCardDate.string(from: flight.date).uppercased()) - \(flight.flightNumber)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                    
                    Text("\(flight.departure.city.isEmpty ? flight.departure.code : flight.departure.city) to \(flight.arrival.city.isEmpty ? flight.arrival.code : flight.arrival.city)")
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Close button aligned with the header content
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(themeManager.currentTheme.colors.surface.opacity(0.8)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            themeManager.currentTheme == .dark ?
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.currentTheme.colors.surface) :
                nil
        )
    }
}

// MARK: - Aircraft Information Card
struct AircraftInfoCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let flight: Flight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(flight.aircraft?.type ?? "Unknown Aircraft")
                .font(.system(size: 24, weight: .regular, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            // Aircraft image placeholder
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
                .frame(height: 180)
                .overlay(
                    Image(systemName: "airplane")
                        .font(.system(size: 48, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                )
            
            // Aircraft specifications grid
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    AircraftSpecItem(
                        title: "Tail No.",
                        value: flight.aircraft?.registration ?? "--"
                    )
                    
                    AircraftSpecItem(
                        title: "ICAO Type",
                        value: flight.aircraft?.icao24?.prefix(4).uppercased() ?? "--"
                    )
                    
                    AircraftSpecItem(
                        title: "Age",
                        value: "--"
                    )
                }
                
                HStack(spacing: 16) {
                    AircraftSpecItem(
                        title: "Cruising Speed",
                        value: "530 mph"
                    )
                    
                    AircraftSpecItem(
                        title: "Range",
                        value: "3,400 mi"
                    )
                    
                    AircraftSpecItem(
                        title: "First Flight",
                        value: "--"
                    )
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.currentTheme.colors.surface)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Aircraft Spec Item
struct AircraftSpecItem: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            
            Text(value)
                .font(.system(size: 20, weight: .regular, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Flight Timeline Card
struct FlightTimelineCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let flight: Flight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Detailed Timeline")
                    .font(.system(size: 24, weight: .regular, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Spacer()
                
                // PRO badge
                Text("PRO")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme == .dark ? 
                        Color(red: 0.8, green: 0.6, blue: 1.0) :  // dark:text-purple-300
                        Color(red: 0.553, green: 0.267, blue: 0.678) // text-purple-700
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeManager.currentTheme == .dark ?
                        Color.purple.opacity(0.3) :  // dark:bg-purple-900/30
                        Color(red: 0.916, green: 0.878, blue: 1.0) // bg-purple-100
                    )
                    .cornerRadius(6)
            }
            
            Text("Scheduled, Estimated, and Actual")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            
            VStack(alignment: .leading, spacing: 24) {
                // Departure section
                VStack(alignment: .leading, spacing: 16) {
                    Text("DEPART")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    TimelineEventRow(
                        label: "Gate Departure",
                        scheduled: flight.departure.displayTime,
                        estimated: flight.departure.actualTime != nil ? 
                            flight.departure.displayTime : flight.departure.displayTime,
                        isDelayed: flight.departure.hasDelay
                    )
                    
                    TimelineEventRow(
                        label: "Runway Departure",
                        scheduled: "0M",
                        estimated: flight.departure.hasDelay ? "10M" : "0M",
                        isDelayed: flight.departure.hasDelay
                    )
                }
                
                // Arrival section (if flight is in progress)
                if flight.status == .inAir || flight.status == .landed {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ARRIVE")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                            .tracking(1)
                        
                        TimelineEventRow(
                            label: "Runway Arrival",
                            scheduled: flight.arrival.displayTime,
                            estimated: flight.arrival.actualTime != nil ?
                                flight.arrival.displayTime : flight.arrival.displayTime,
                            isDelayed: flight.arrival.hasDelay
                        )
                        
                        TimelineEventRow(
                            label: "Gate Arrival",
                            scheduled: "0M",
                            estimated: flight.arrival.hasDelay ? "15M" : "0M",
                            isDelayed: flight.arrival.hasDelay
                        )
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.currentTheme.colors.surface)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Timeline Event Row
struct TimelineEventRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let label: String
    let scheduled: String
    let estimated: String
    let isDelayed: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Schedule")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                
                Text(scheduled)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
            }
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Estimated")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                
                Text(estimated)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundColor(isDelayed ? 
                        (themeManager.currentTheme == .dark ? 
                            Color(red: 0.937, green: 0.384, blue: 0.384) :  // dark:text-red-400
                            Color.red                                        // text-red-500
                        ) : 
                        (themeManager.currentTheme == .dark ? 
                            Color(red: 0.439, green: 0.859, blue: 0.576) :  // dark:text-green-400
                            Color.green                                      // text-green-500
                        )
                    )
            }
        }
    }
}

#Preview {
    FlightDetailsInSheet(
        flight: Flight.sample,
        onClose: {}
    )
    .environmentObject(ThemeManager())
}