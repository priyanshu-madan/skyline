//
//  PlaceLogView.swift
//  SkyLine
//
//  The home surface of the place log: every place the user has ever logged,
//  accumulated across trips and years, grouped by country, filterable by
//  verdict, searchable by name / city / country.
//
//  One place = one row, no matter how many times it was visited. The visit
//  count rides in the row subtitle; a place is never duplicated.
//
//  All three verdicts are peers here. "Skip" is not negative chrome — it is the
//  answer no saved-places list can record, so it gets the same chip, the same
//  size and the same one-tap filter as "Worth it".
//

import SwiftUI
import Photos
import UIKit

// MARK: - Grouping Mode
/// How the log is laid out. `country` is the default because the question the
/// user usually arrives with is geographic ("what did I like in Japan").
enum PlaceLogGrouping: String, CaseIterable, Identifiable, Hashable {
    case country
    case recent
    case mostVisited

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .country: return "By country"
        case .recent: return "Most recent"
        case .mostVisited: return "Most visited"
        }
    }

    var systemImage: String {
        switch self {
        case .country: return "globe"
        case .recent: return "clock"
        case .mostVisited: return "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
}

// MARK: - Place Log View
struct PlaceLogView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var placeStore = PlaceStore.shared

    /// Optional escape hatch for the empty state. When nil the empty state
    /// renders as copy only — `PlaceLogEmptyStateView` hides a button whose
    /// action is missing.
    private let onAddTrip: (() -> Void)?

    @State private var searchText: String = ""
    @State private var verdictFilter: Verdict?
    @State private var grouping: PlaceLogGrouping = .country
    @State private var path: [Place] = []

    init(onAddTrip: (() -> Void)? = nil) {
        self.onAddTrip = onAddTrip
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(themeManager.currentTheme.colors.background.ignoresSafeArea())
                .navigationTitle("Places")
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search places, cities, countries")
                )
                .toolbar { toolbarContent }
                .navigationDestination(for: Place.self) { place in
                    PlaceDetailView(place: place)
                }
        }
        .tint(themeManager.currentTheme.colors.primary)
        .task { await placeStore.syncIfNeeded() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if placeStore.places.isEmpty {
            ScrollView {
                PlaceLogEmptyStateView(
                    state: .noTrips,
                    onPrimaryAction: onAddTrip
                )
                .padding(.top, AppSpacing.xl)
            }
            .refreshable { await placeStore.forceSync() }
            .skylineScrollEdges()
        } else {
            logScroll
        }
    }

    private var logScroll: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: AppSpacing.md,
                pinnedViews: [.sectionHeaders]
            ) {
                summaryHeader
                VerdictPicker(selection: $verdictFilter)
                resultsBar

                if visibleSummaries.isEmpty {
                    noMatches
                } else {
                    resultBody
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.xxl)
            .animation(listAnimation, value: verdictFilter)
            .animation(listAnimation, value: grouping)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await placeStore.forceSync() }
        .skylineScrollEdges()
    }

    @ViewBuilder
    private var resultBody: some View {
        switch grouping {
        case .country:
            ForEach(countryGroups) { group in
                Section {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(group.summaries) { summary in
                            row(for: summary)
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                } header: {
                    countryHeader(group)
                }
            }
        case .recent, .mostVisited:
            VStack(spacing: AppSpacing.sm) {
                ForEach(visibleSummaries) { summary in
                    row(for: summary)
                }
            }
        }
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    // MARK: - Header

    private var summaryHeader: some View {
        let theme = themeManager.currentTheme
        let placeCount = placeStore.places.count
        let countryCount = placeStore.countryCount
        let worthItCount = placeStore.worthItCount

        return SkyLineGlassPanel(spacing: AppSpacing.sm) {
            HStack(spacing: 0) {
                statColumn(
                    value: placeCount,
                    label: placeCount == 1 ? "place" : "places",
                    tint: theme.colors.text
                )
                statDivider
                statColumn(
                    value: countryCount,
                    label: countryCount == 1 ? "country" : "countries",
                    tint: theme.colors.text
                )
                statDivider
                statColumn(
                    value: worthItCount,
                    label: "worth it",
                    tint: theme.colors.verdictWorthIt
                )
            }
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.sm)
            .frame(maxWidth: .infinity)
            .skylineGlassCard(theme: theme)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(placeCount) places in \(countryCount) countries. \(worthItCount) rated worth it.")
        )
    }

    private func statColumn(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text("\(value)")
                .appFont(.title, lineLimit: .exactly(1))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .appFont(.footnote, lineLimit: .exactly(1))
                .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(themeManager.currentTheme.colors.border)
            .frame(width: 1, height: 28)
            .accessibilityHidden(true)
    }

    // MARK: - Results Bar

    private var resultsBar: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.sm) {
            Text(resultsText)
                .appFont(.caption, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.textSecondary)

            Spacer(minLength: AppSpacing.sm)

            if isFiltering {
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    withAnimation(listAnimation) {
                        verdictFilter = nil
                        searchText = ""
                    }
                } label: {
                    Text("Show all")
                        .appFont(.caption, lineLimit: .exactly(1))
                        .padding(.horizontal, AppSpacing.xs)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityLabel(Text("Clear filters"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultsText: String {
        let count = visibleSummaries.count
        let noun = count == 1 ? "place" : "places"
        var text = "\(count) \(noun)"
        if let verdictFilter {
            text += " · \(verdictFilter.displayName)"
        }
        let query = trimmedSearch
        if !query.isEmpty {
            text += " · \"\(query)\""
        }
        return text
    }

    // MARK: - Country Header

    private func countryHeader(_ group: PlaceCountryGroup) -> some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.sm) {
            if let flag = PlaceLogView.flagEmoji(for: group.countryCode) {
                Text(flag)
                    .appFont(.bodySmall, lineLimit: .exactly(1))
            }

            Text(group.countryName)
                .appFont(.captionBold, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.text)

            Text("\(group.placeCount)")
                .appFont(.footnote, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.textSecondary)

            if group.worthItCount > 0 {
                Label("\(group.worthItCount)", systemImage: Verdict.worthIt.systemImage)
                    .labelStyle(.titleAndIcon)
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.verdictWorthIt)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(.horizontal, AppSpacing.md - 2)
        .padding(.vertical, AppSpacing.sm - 2)
        .skylineGlassCapsule(theme: theme)
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(countryHeaderAccessibilityLabel(group)))
        .accessibilityAddTraits(.isHeader)
    }

    private func countryHeaderAccessibilityLabel(_ group: PlaceCountryGroup) -> String {
        let noun = group.placeCount == 1 ? "place" : "places"
        var text = "\(group.countryName), \(group.placeCount) \(noun)"
        if group.worthItCount > 0 {
            text += ", \(group.worthItCount) worth it"
        }
        return text
    }

    // MARK: - Row

    private func row(for summary: PlaceSummary) -> some View {
        PlaceLogRow(
            summary: summary,
            photoIdentifier: placeStore
                .mostRecentVisit(for: summary.place.id)?
                .photoLocalIdentifiers
                .first
        ) {
            path.append(summary.place)
        }
    }

    // MARK: - No Matches
    /// A search / filter miss, which is not the same thing as an empty log:
    /// `PlaceLogEmptyStateView` owns the "you have nothing yet" story and its
    /// copy is about photos and trip dates, which would be wrong here.
    private var noMatches: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.mono(.title2))
                .foregroundStyle(theme.colors.textSecondary)
                .symbolRenderingMode(.hierarchical)

            Text("Nothing matches")
                .appFont(.bodyBold)
                .foregroundStyle(theme.colors.text)

            Text(noMatchesMessage)
                .appFont(.bodySmall)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    private var noMatchesMessage: String {
        if let verdictFilter, !trimmedSearch.isEmpty {
            return "No \(verdictFilter.displayName.lowercased()) place matches \"\(trimmedSearch)\"."
        }
        if let verdictFilter {
            return "You have not marked anything \(verdictFilter.displayName.lowercased()) yet."
        }
        return "No place, city or country matches \"\(trimmedSearch)\"."
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await placeStore.forceSync() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: placeStore.isSyncing && !reduceMotion)
            }
            .disabled(placeStore.isSyncing)
            .accessibilityLabel(Text("Sync places"))
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Group by", selection: $grouping) {
                    ForEach(PlaceLogGrouping.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: grouping.systemImage)
            }
            .accessibilityLabel(Text("Group places"))
        }
    }

    // MARK: - Data

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFiltering: Bool {
        verdictFilter != nil || !trimmedSearch.isEmpty
    }

    /// Search first (it is the narrower predicate), then verdict. When there is
    /// no query the store's own `places(with:)` does the verdict pass.
    private var baseSummaries: [PlaceSummary] {
        let query = trimmedSearch

        guard !query.isEmpty else {
            guard let verdictFilter else { return placeStore.placeSummaries }
            return placeStore.places(with: verdictFilter)
        }

        let searched = placeStore.searchPlaces(query)
        guard let verdictFilter else { return searched }
        return searched.filter { $0.verdict == verdictFilter }
    }

    /// The filtered set in the order the current grouping wants it.
    /// `placeSummaries` is already newest-first, which is what `.recent` and the
    /// inside of each country section want.
    private var visibleSummaries: [PlaceSummary] {
        let base = baseSummaries

        switch grouping {
        case .country, .recent:
            return base
        case .mostVisited:
            let allowed = Set(base.map { $0.id })
            return placeStore
                .mostVisitedPlaces(limit: placeStore.places.count)
                .filter { allowed.contains($0.id) }
        }
    }

    /// Countries over the *filtered* set, so a verdict filter empties a country
    /// section instead of leaving a header with nothing under it. Ordering
    /// matches `PlaceStore.placesByCountry`: most places first, then A-Z.
    private var countryGroups: [PlaceCountryGroup] {
        let grouped = Dictionary(grouping: visibleSummaries) { summary -> String in
            let country = summary.place.country ?? ""
            return country.isEmpty ? "Unknown" : country
        }

        return grouped
            .map { countryName, summaries in
                PlaceCountryGroup(
                    countryName: countryName,
                    countryCode: summaries.compactMap { $0.place.countryCode }.first,
                    summaries: summaries
                )
            }
            .sorted { lhs, rhs in
                if lhs.placeCount != rhs.placeCount { return lhs.placeCount > rhs.placeCount }
                return lhs.countryName < rhs.countryName
            }
    }

    // MARK: - Flag

    /// ISO 3166-1 alpha-2 -> regional indicator pair. Returns nil for anything
    /// that is not two ASCII letters, so a junk code never renders as tofu.
    static func flagEmoji(for countryCode: String?) -> String? {
        guard let countryCode, countryCode.count == 2 else { return nil }

        let base: UInt32 = 127_397 // 0x1F1E6 - Unicode scalar for "A"
        var scalars = String.UnicodeScalarView()

        for scalar in countryCode.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90,
                  let indicator = UnicodeScalar(base + scalar.value) else {
                return nil
            }
            scalars.append(indicator)
        }

        return String(scalars)
    }
}

// MARK: - Place Log Row
/// One place, one row — however many times it was visited. `PlaceCard` takes a
/// resolved `UIImage`, so the most recent visit's first photo is loaded through
/// the shared `PhotoAssetImageLoader` (thumbnail size, no iCloud download) and
/// cancelled on disappear.
private struct PlaceLogRow: View {
    let summary: PlaceSummary
    let photoIdentifier: String?
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        PlaceCard(
            name: summary.place.name,
            date: summary.lastVisitDate ?? summary.place.createdAt,
            subtitle: subtitle,
            verdict: summary.verdict,
            image: image,
            style: .row,
            showsYear: true,
            onTap: onTap
        )
        .task(id: photoIdentifier) { await loadThumbnail() }
        .onDisappear {
            PhotoAssetImageLoader.shared.cancel(requestID)
            requestID = PHInvalidImageRequestID
        }
    }

    /// "Shibuya, Japan · 3 visits". The count is why a twice-visited place never
    /// needs a second row.
    private var subtitle: String? {
        var parts: [String] = []

        let locality = summary.place.displayLocality
        if !locality.isEmpty {
            parts.append(locality)
        }
        if summary.visitCount > 1 {
            parts.append(summary.visitCountText)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @MainActor
    private func loadThumbnail() async {
        PhotoAssetImageLoader.shared.cancel(requestID)
        requestID = PHInvalidImageRequestID
        image = nil

        guard let photoIdentifier else { return }

        // Returns an empty result rather than throwing when the library is
        // unauthorized or the asset was deleted - the card falls back to its
        // own placeholder.
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [photoIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }

        requestID = PhotoAssetImageLoader.shared.requestImage(for: asset, size: .thumbnail) { loaded, _ in
            guard let loaded else { return }
            self.image = loaded
        }
    }
}

// MARK: - Previews
#Preview("Place log") {
    PlaceLogView()
        .environmentObject(ThemeManager())
}
