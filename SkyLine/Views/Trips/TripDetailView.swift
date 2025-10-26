//
//  TripDetailView.swift
//  SkyLine
//
//  Detailed trip view with vertical timeline
//

import SwiftUI

struct TripDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss
    
    let trip: Trip
    @State private var showingAddEntry = false
    @State private var selectedEntry: TripEntry?
    @State private var refreshID = UUID()
    
    private var entries: [TripEntry] {
        tripStore.getEntries(for: trip.id).sortedByTimestamp()
    }
    
    private var groupedEntries: [(Date, [TripEntry])] {
        tripStore.getEntriesGroupedByDay(for: trip.id)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        // Trip header
                        TripHeaderView(trip: trip)
                        
                        // Timeline content
                        if entries.isEmpty {
                            EmptyTimelineView(onAddEntry: { showingAddEntry = true })
                        } else {
                            TimelineView(
                                groupedEntries: groupedEntries,
                                onEntryTap: { entry in
                                    selectedEntry = entry
                                }
                            )
                        }
                    }
                }
                
                // Floating add button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        Button {
                            showingAddEntry = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(themeManager.currentTheme.colors.primary)
                                .clipShape(Circle())
                                .shadow(
                                    color: themeManager.currentTheme.colors.primary.opacity(0.3),
                                    radius: 8,
                                    x: 0,
                                    y: 4
                                )
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            // Edit trip
                        } label: {
                            Label("Edit Trip", systemImage: "pencil")
                        }
                        
                        Button {
                            // Share trip
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            // Delete trip
                        } label: {
                            Label("Delete Trip", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddEntryView(tripId: trip.id)
                .environmentObject(themeManager)
                .environmentObject(tripStore)
        }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailView(entry: entry)
                .environmentObject(themeManager)
        }
        .id(refreshID)
        .onAppear {
            Task {
                await tripStore.fetchEntriesForTrip(trip.id)
                refreshID = UUID()
            }
        }
    }
}

// MARK: - Trip Header
struct TripHeaderView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let trip: Trip
    
    var body: some View {
        VStack(spacing: 16) {
            // Trip image
            TripHeaderImageView(trip: trip)
                .frame(height: 200)
                .clipped()
            
            // Trip info
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(trip.title)
                        .font(.system(.largeTitle, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                        .multilineTextAlignment(.center)
                    
                    Text(trip.destination)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("Duration")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        
                        Text(trip.durationText)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                    
                    VStack(spacing: 4) {
                        Text("Status")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            
                            Text(trip.statusText)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(themeManager.currentTheme.colors.text)
                        }
                    }
                    
                    VStack(spacing: 4) {
                        Text("Dates")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        
                        Text(trip.dateRangeText)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                }
                
                if let description = trip.description, !description.isEmpty {
                    Text(description)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(themeManager.currentTheme.colors.background)
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

// MARK: - Trip Header Image
struct TripHeaderImageView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let trip: Trip
    
    var body: some View {
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
            
            // Destination image if available
            if let coverImageURL = trip.coverImageURL,
               let url = URL(string: coverImageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                        .scaleEffect(0.8)
                }
            } else {
                // Fallback with destination name
                VStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .font(.system(size: 48, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(trip.destination)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
            }
        }
    }
}

// MARK: - Timeline View
struct TimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let groupedEntries: [(Date, [TripEntry])]
    let onEntryTap: (TripEntry) -> Void
    
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(groupedEntries.enumerated()), id: \.offset) { dayIndex, dayGroup in
                let (date, entries) = dayGroup
                
                // Day header
                TimelineDayHeader(date: date, entryCount: entries.count)
                    .padding(.horizontal, 20)
                    .padding(.top, dayIndex == 0 ? 20 : 32)
                    .padding(.bottom, 16)
                
                // Entries for this day
                ForEach(Array(entries.enumerated()), id: \.element.id) { entryIndex, entry in
                    TimelineEntryView(
                        entry: entry,
                        isLast: entryIndex == entries.count - 1 && dayIndex == groupedEntries.count - 1,
                        onTap: { onEntryTap(entry) }
                    )
                    .padding(.horizontal, 20)
                }
            }
            
            // Bottom padding
            Color.clear
                .frame(height: 100)
        }
    }
}

// MARK: - Timeline Day Header
struct TimelineDayHeader: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let date: Date
    let entryCount: Int
    
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("\(entryCount) \(entryCount == 1 ? "entry" : "entries")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Timeline Entry View
struct TimelineEntryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let entry: TripEntry
    let isLast: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline line and dot
            VStack(spacing: 0) {
                // Dot
                ZStack {
                    Circle()
                        .fill(themeManager.currentTheme.colors.background)
                        .frame(width: 16, height: 16)
                    
                    Circle()
                        .fill(entryTypeColor)
                        .frame(width: 12, height: 12)
                }
                
                // Vertical line (if not last)
                if !isLast {
                    Rectangle()
                        .fill(themeManager.currentTheme.colors.border)
                        .frame(width: 2)
                        .frame(minHeight: 60)
                }
            }
            .frame(width: 16)
            
            // Entry content
            TimelineEntryCard(entry: entry, onTap: onTap)
                .padding(.bottom, isLast ? 0 : 16)
        }
    }
    
    private var entryTypeColor: Color {
        switch entry.entryType.color {
        case "orange":
            return .orange
        case "purple":
            return .purple
        case "blue":
            return .blue
        case "green":
            return .green
        case "red":
            return .red
        case "pink":
            return .pink
        case "yellow":
            return .yellow
        default:
            return .gray
        }
    }
}

// MARK: - Timeline Entry Card
struct TimelineEntryCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let entry: TripEntry
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with type and time
            HStack {
                HStack(spacing: 6) {
                    Text(entry.entryType.emoji)
                        .font(.system(.body, design: .monospaced))
                    
                    Text(entry.entryType.displayName)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                }
                
                Spacer()
                
                Text(entry.timeText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            // Title and content
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(3)
                }
            }
            
            // Location if available
            if !entry.displayLocation.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Text(entry.displayLocation)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .lineLimit(1)
                }
            }
            
            // Images if available
            if entry.hasImages {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entry.imageURLs.prefix(3), id: \.self) { imageURL in
                            if let url = URL(string: imageURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        .clipped()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(themeManager.currentTheme.colors.surface)
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        )
                                }
                            }
                        }
                        
                        if entry.imageURLs.count > 3 {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(themeManager.currentTheme.colors.surface)
                                    .frame(width: 60, height: 60)
                                
                                Text("+\(entry.imageURLs.count - 3)")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(16)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
        )
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Empty Timeline
struct EmptyTimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let onAddEntry: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 48, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                
                Text("Start Your Timeline")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("Add your first entry to document this amazing trip")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                onAddEntry()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add First Entry")
                }
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 40)
    }
}

// MARK: - Placeholder Views

struct EntryDetailView: View {
    let entry: TripEntry
    
    var body: some View {
        Text("Entry Detail View - \(entry.title)")
            .font(.system(.title, design: .monospaced))
    }
}

#Preview {
    TripDetailView(trip: Trip.sample)
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}