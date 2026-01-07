//
//  ReviewItineraryView.swift
//  SkyLine
//
//  Review and edit AI-parsed itinerary before adding to trip
//

import SwiftUI

struct ReviewItineraryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var editableItinerary: ParsedItinerary
    @State private var selectedItems: Set<String> = []
    @State private var showingEditItem: ItineraryItem?
    @State private var showingTripCreation = false
    @State private var suggestedTrip: Trip?
    
    let originalItinerary: ParsedItinerary
    let onConfirm: (ParsedItinerary) -> Void
    let onCancel: () -> Void
    
    init(parsedItinerary: ParsedItinerary, onConfirm: @escaping (ParsedItinerary) -> Void, onCancel: @escaping () -> Void) {
        self.originalItinerary = parsedItinerary
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._editableItinerary = State(initialValue: parsedItinerary)
        self._suggestedTrip = State(initialValue: parsedItinerary.suggestTrip())
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with summary
                headerSection
                
                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Processing info
                        processingInfoCard
                        
                        // Trip suggestion
                        if let trip = suggestedTrip {
                            tripSuggestionCard(trip)
                        }
                        
                        // Items list
                        itemsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100) // Space for bottom buttons
                }
                
                // Bottom action buttons
                bottomActionButtons
            }
            .navigationTitle("Review Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Select All") {
                        toggleSelectAll()
                    }
                    .disabled(editableItinerary.items.isEmpty)
                }
            }
        }
        .sheet(item: $showingEditItem) { item in
            EditItineraryItemView(
                item: item,
                onSave: { updatedItem in
                    updateItem(updatedItem)
                    showingEditItem = nil
                },
                onCancel: {
                    showingEditItem = nil
                }
            )
        }
        .sheet(isPresented: $showingTripCreation) {
            if let trip = suggestedTrip {
                CreateTripFromItineraryView(
                    suggestedTrip: trip,
                    itinerary: editableItinerary,
                    onConfirm: { finalItinerary in
                        onConfirm(finalItinerary)
                    },
                    onCancel: {
                        showingTripCreation = false
                    }
                )
            }
        }
        .onAppear {
            // Pre-select all items
            selectedItems = Set(editableItinerary.items.map(\.id))
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parsed \(editableItinerary.items.count) items")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    if let destination = editableItinerary.metadata.destination {
                        Text(destination)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }
                
                Spacer()
                
                // Confidence indicator
                confidenceIndicator
            }
            
            if let dateRange = editableItinerary.dateRange {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                    
                    Text("\(dateRange.start.formatted(date: .abbreviated, time: .omitted)) - \(dateRange.end.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(themeManager.currentTheme.colors.surface)
    }
    
    private var confidenceIndicator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Confidence")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            
            HStack(spacing: 4) {
                Text("\(Int(editableItinerary.averageConfidence * 100))%")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(confidenceColor)
                
                Circle()
                    .fill(confidenceColor)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private var confidenceColor: Color {
        let confidence = editableItinerary.averageConfidence
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .orange }
        return .red
    }
    
    // MARK: - Processing Info
    
    private var processingInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                
                Text("Processing Info")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Source", editableItinerary.processingInfo.sourceType.displayName)
                infoRow("Model", editableItinerary.processingInfo.modelUsed)
                infoRow("Processing Time", String(format: "%.1fs", editableItinerary.processingInfo.processingTime))
                infoRow("Items Found", "\(editableItinerary.processingInfo.successfullyParsedItems)")
            }
        }
        .padding()
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
    
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundColor(themeManager.currentTheme.colors.text)
        }
    }
    
    // MARK: - Trip Suggestion
    
    private func tripSuggestionCard(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                
                Text("Suggested Trip")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Spacer()
                
                Button("Edit") {
                    showingTripCreation = true
                }
                .foregroundColor(themeManager.currentTheme.colors.primary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text(trip.destination)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                
                Text(trip.dateRangeText)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
        }
        .padding()
        .background(themeManager.currentTheme.colors.primary.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.colors.primary.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Items Section
    
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Timeline Items")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Spacer()
                
                Text("\(selectedItems.count)/\(editableItinerary.items.count) selected")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(editableItinerary.sortedItems) { item in
                    ItineraryItemCard(
                        item: item,
                        isSelected: selectedItems.contains(item.id),
                        onToggleSelection: {
                            toggleSelection(item.id)
                        },
                        onEdit: {
                            showingEditItem = item
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Bottom Actions
    
    private var bottomActionButtons: some View {
        VStack(spacing: 12) {
            Divider()
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(themeManager.currentTheme.colors.surface)
                .cornerRadius(12)
                
                Button("Create Trip") {
                    confirmItinerary()
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    selectedItems.isEmpty 
                    ? Color.gray 
                    : themeManager.currentTheme.colors.primary
                )
                .cornerRadius(12)
                .disabled(selectedItems.isEmpty)
            }
            .padding(.horizontal, 16)
        }
        .background(themeManager.currentTheme.colors.background)
    }
    
    // MARK: - Methods
    
    private func toggleSelectAll() {
        if selectedItems.count == editableItinerary.items.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(editableItinerary.items.map(\.id))
        }
    }
    
    private func toggleSelection(_ itemId: String) {
        if selectedItems.contains(itemId) {
            selectedItems.remove(itemId)
        } else {
            selectedItems.insert(itemId)
        }
    }
    
    private func updateItem(_ updatedItem: ItineraryItem) {
        if let index = editableItinerary.items.firstIndex(where: { $0.id == updatedItem.id }) {
            var newItems = editableItinerary.items
            newItems[index] = updatedItem
            
            editableItinerary = ParsedItinerary(
                id: editableItinerary.id,
                items: newItems,
                metadata: editableItinerary.metadata,
                processingInfo: editableItinerary.processingInfo
            )
        }
    }
    
    private func confirmItinerary() {
        let selectedItemsList = editableItinerary.items.filter { selectedItems.contains($0.id) }
        
        let finalItinerary = ParsedItinerary(
            id: editableItinerary.id,
            items: selectedItemsList,
            metadata: editableItinerary.metadata,
            processingInfo: editableItinerary.processingInfo
        )
        
        onConfirm(finalItinerary)
    }
}

// MARK: - Itinerary Item Card

struct ItineraryItemCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let item: ItineraryItem
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection checkbox
            Button {
                onToggleSelection()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.textSecondary)
            }
            .padding(.top, 2)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Text(item.activityType.emoji)
                            .font(.system(size: 16))
                        
                        Text(item.activityType.displayName)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .textCase(.uppercase)
                    }
                    
                    Spacer()
                    
                    Text(item.dateTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    // Confidence indicator
                    Circle()
                        .fill(confidenceColor(item.confidence))
                        .frame(width: 6, height: 6)
                }
                
                // Title and content
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    if !item.content.isEmpty {
                        Text(item.content)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                
                // Location
                if let location = item.location {
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.system(.caption))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        
                        Text(location.displayName)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            
            // Edit button
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
            }
            .padding(.top, 2)
        }
        .padding()
        .background(isSelected ? themeManager.currentTheme.colors.primary.opacity(0.1) : themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.border, lineWidth: 1)
        )
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .orange }
        return .red
    }
}

// Placeholder views - these would be implemented in separate files
struct EditItineraryItemView: View {
    let item: ItineraryItem
    let onSave: (ItineraryItem) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        Text("Edit Item View - \(item.title)")
    }
}

struct CreateTripFromItineraryView: View {
    let suggestedTrip: Trip
    let itinerary: ParsedItinerary
    let onConfirm: (ParsedItinerary) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        Text("Create Trip View - \(suggestedTrip.title)")
    }
}

#Preview {
    ReviewItineraryView(
        parsedItinerary: .sample,
        onConfirm: { _ in },
        onCancel: { }
    )
    .environmentObject(ThemeManager())
}