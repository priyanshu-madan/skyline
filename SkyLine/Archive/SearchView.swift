//
//  SearchView.swift
//  SkyLine
//
//  Flight search screen with OCR and filtering capabilities
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    
    @State private var searchText = ""
    @State private var searchResults: [Flight] = []
    @State private var isSearching = false
    @State private var showingPhotoImport = false
    @State private var showingFilters = false
    @State private var selectedAirline = "All"
    @State private var selectedStatus = "All"
    @State private var sortBy: SortOption = .time
    @State private var sortOrder: SortOrder = .ascending
    
    // Photo import state (will be handled differently for iOS 15)
    @State private var showingImagePicker = false
    
    // Toast notifications
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var toastType: ToastType = .success
    
    private let searchSuggestions = [
        "AA123", "UA456", "DL789", "WN101",
        "LAX to JFK", "SFO to LAX", "ORD to LAX",
        "UAL", "DAL", "AAL", "SWA"
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                themeManager.currentTheme.colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search header
                    searchHeader
                    
                    // Content
                    if isSearching {
                        loadingView
                    } else if !searchResults.isEmpty {
                        resultsView
                    } else if !searchText.isEmpty {
                        emptySearchView
                    } else {
                        defaultContentView
                    }
                }
            }
            .navigationTitle("Skyline")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingPhotoImport) {
                VStack(spacing: 20) {
                    Text("📷")
                        .font(.system(size: 64))
                    Text("Photo Import")
                        .font(.title)
                    Text("Photo import feature coming soon!")
                        .foregroundColor(.secondary)
                    
                    Button("Cancel") {
                        showingPhotoImport = false
                    }
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()
            }
            .overlay(
                // Toast notification
                VStack {
                    if showToast {
                        ToastView(message: toastMessage, type: toastType, theme: themeManager)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .animation(.spring(), value: showToast)
            )
        }
        .task {
            // Auto-hide toast after 3 seconds
            if showToast {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showToast = false
            }
        }
    }
    
    private var searchHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            searchInputView
            photoImportButtonView
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.sm)
        .background(themeManager.currentTheme.colors.background)
    }
    
    private var searchInputView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            
            TextField("Flight number or route (e.g., AA123, LAX to JFK)", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(AppTypography.body)
                .onSubmit {
                    performSearch()
                }
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                
                Button(action: performSearch) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(AppRadius.md)
    }
    
    private var photoImportButtonView: some View {
        Button(action: { showingPhotoImport = true }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "camera")
                Text("Import from Photo")
                    .font(AppTypography.body)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .foregroundColor(themeManager.currentTheme.colors.primary)
            .padding(AppSpacing.sm)
            .background(themeManager.currentTheme.colors.surface)
            .cornerRadius(AppRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(themeManager.currentTheme.colors.primary, lineWidth: 1)
            )
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(themeManager.currentTheme.colors.primary)
            
            Text("Searching flights...")
                .font(AppTypography.headline)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            Text("This may take a few seconds")
                .font(AppTypography.caption)
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            
            // Skeleton loading cards
            VStack(spacing: AppSpacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonCardView(theme: themeManager)
                }
            }
            .padding(.top, AppSpacing.lg)
        }
        .padding(AppSpacing.xl)
    }
    
    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Results header with filters
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
                    Text("\(filteredResults.count) of \(searchResults.count) flight\(searchResults.count != 1 ? "s" : "")")
                        .font(AppTypography.bodyBold)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text("via AviationStack")
                        .font(AppTypography.caption)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                }
                
                Spacer()
                
                Button(action: { showingFilters.toggle() }) {
                    HStack(spacing: AppSpacing.xs) {
                        Text("Filters & Sort")
                        Image(systemName: showingFilters ? "chevron.up" : "chevron.down")
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            
            // Filter options (collapsible)
            if showingFilters {
                filterOptionsView
                    .transition(.slide.combined(with: .opacity))
            }
            
            // Results list
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach(filteredResults) { flight in
                        FlightCardView(
                            flight: flight,
                            showSaveButton: !flightStore.isFlightSaved(flight.id),
                            showDeleteButton: false,
                            theme: themeManager
                        ) {
                            // On tap - show details
                            flightStore.setSelectedFlight(flight)
                        } onSave: {
                            // On save
                            Task {
                                let result = await flightStore.addFlight(flight)
                                switch result {
                                case .success:
                                    showToastMessage("Flight \(flight.flightNumber) saved!", type: .success)
                                case .failure(let error):
                                    showToastMessage(error.localizedDescription, type: .error)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, AppSpacing.sm)
            }
        }
    }
    
    private var filterOptionsView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Airline filter
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Airline")
                    .font(AppTypography.captionBold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        FilterChipView(
                            title: "All",
                            isSelected: selectedAirline == "All",
                            theme: themeManager
                        ) {
                            selectedAirline = "All"
                        }
                        
                        ForEach(availableAirlines, id: \.self) { airline in
                            FilterChipView(
                                title: airline,
                                isSelected: selectedAirline == airline,
                                theme: themeManager
                            ) {
                                selectedAirline = airline
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }
            
            // Sort options
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Sort By")
                    .font(AppTypography.captionBold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                HStack(spacing: AppSpacing.xs) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        FilterChipView(
                            title: option.displayName,
                            isSelected: sortBy == option,
                            theme: themeManager
                        ) {
                            sortBy = option
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { sortOrder = sortOrder == .ascending ? .descending : .ascending }) {
                        HStack(spacing: AppSpacing.xs / 2) {
                            Text(sortOrder == .ascending ? "↑ Asc" : "↓ Desc")
                        }
                        .font(AppTypography.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(themeManager.currentTheme.colors.success)
                        .cornerRadius(AppRadius.full)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
            }
        }
        .padding(AppSpacing.md)
        .background(themeManager.currentTheme.colors.surface)
    }
    
    private var emptySearchView: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("🔍")
                .font(.system(size: 64))
            
            Text("No flights found")
                .font(AppTypography.headline)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            Text("We couldn't find any flights matching \"\(searchText)\". Try a different search term.")
                .font(AppTypography.body)
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
            
            Button("Try Different Search") {
                searchText = ""
                searchResults.removeAll()
            }
            .font(AppTypography.bodyBold)
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(themeManager.currentTheme.colors.primary)
            .cornerRadius(AppRadius.md)
        }
        .padding(.top, AppSpacing.xxl)
    }
    
    private var defaultContentView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Recent searches
                if !flightStore.searchHistory.isEmpty {
                    recentSearchesSection
                }
                
                // Search examples
                searchExamplesSection
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
        }
    }
    
    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Recent Searches (\(flightStore.searchHistory.count))")
                    .font(AppTypography.bodyBold)
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Spacer()
                
                Button("Clear") {
                    flightStore.clearSearchHistory()
                }
                .font(AppTypography.captionBold)
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(themeManager.currentTheme.colors.error)
                .cornerRadius(AppRadius.xs)
            }
            
            VStack(spacing: AppSpacing.xs) {
                ForEach(Array(flightStore.searchHistory.prefix(3)), id: \.self) { search in
                    Button(action: {
                        searchText = search
                        performSearch()
                    }) {
                        HStack {
                            Text(search)
                                .font(AppTypography.body)
                                .foregroundColor(themeManager.currentTheme.colors.text)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.left")
                                .font(AppTypography.caption)
                                .foregroundColor(themeManager.currentTheme.colors.primary)
                        }
                        .padding(AppSpacing.sm)
                        .background(themeManager.currentTheme.colors.surface)
                        .cornerRadius(AppRadius.sm)
                    }
                }
                
                if flightStore.searchHistory.count > 3 {
                    Text("+\(flightStore.searchHistory.count - 3) more")
                        .font(AppTypography.caption)
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .italic()
                }
            }
        }
        .padding(AppSpacing.md)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(AppRadius.md)
    }
    
    private var searchExamplesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Try These Airlines")
                .font(AppTypography.bodyBold)
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: AppSpacing.sm) {
                ForEach(["UAL", "DAL", "AAL", "AA", "UA", "DL"], id: \.self) { example in
                    Button(action: {
                        searchText = example
                        performSearch()
                    }) {
                        Text(example)
                            .font(AppTypography.captionBold)
                            .foregroundColor(.white)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(themeManager.currentTheme.colors.primary)
                            .cornerRadius(AppRadius.sm)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(AppRadius.md)
    }
    
    // MARK: - Computed Properties
    
    private var availableAirlines: [String] {
        Array(Set(searchResults.map(\.airline))).sorted()
    }
    
    private var filteredResults: [Flight] {
        var filtered = searchResults
        
        // Apply airline filter
        if selectedAirline != "All" {
            filtered = filtered.filter { $0.airline.lowercased().contains(selectedAirline.lowercased()) }
        }
        
        // Apply sorting
        filtered.sort { lhs, rhs in
            let comparison: Bool
            switch sortBy {
            case .time:
                comparison = lhs.departure.time < rhs.departure.time
            case .airline:
                comparison = lhs.airline < rhs.airline
            case .status:
                comparison = lhs.status.rawValue < rhs.status.rawValue
            }
            return sortOrder == .ascending ? comparison : !comparison
        }
        
        return filtered
    }
    
    // MARK: - Methods
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSearching = true
        searchResults.removeAll()
        
        Task {
            let result = await flightStore.searchFlights(query: searchText)
            
            await MainActor.run {
                isSearching = false
                switch result {
                case .success(let flights):
                    searchResults = flights
                case .failure(let error):
                    showToastMessage(error.localizedDescription, type: .error)
                }
            }
        }
    }
    
    private func handleFlightExtracted(_ extractedFlight: Flight) async {
        let result = await flightStore.addFlight(extractedFlight)
        switch result {
        case .success:
            showToastMessage("✈️ Flight \(extractedFlight.flightNumber) imported from photo successfully!", type: .success)
        case .failure(let error):
            showToastMessage(error.localizedDescription, type: .error)
        }
    }
    
    private func showToastMessage(_ message: String, type: ToastType) {
        toastMessage = message
        toastType = type
        showToast = true
        
        // Auto-hide after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showToast = false
        }
    }
}

// MARK: - Supporting Types

enum SortOption: CaseIterable {
    case time, airline, status
    
    var displayName: String {
        switch self {
        case .time: return "Time"
        case .airline: return "Airline"
        case .status: return "Status"
        }
    }
}

enum SortOrder {
    case ascending, descending
}

enum ToastType {
    case success, error, info
}

#Preview {
    SearchView()
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
}