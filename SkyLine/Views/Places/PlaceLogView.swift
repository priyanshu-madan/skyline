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
//  answer no saved-places list can record, so it gets the same tile, the same
//  size and the same one-tap filter as "Worth it".
//
//  LAYOUT NOTES, because this screen has to survive a hundred rows.
//
//  * The list is continuous, not a stack of cards. A hundred glass cards is a
//    wall of specular edges; a hundred flat rows sharing one unbroken column of
//    verdict rails is a ribbon you can read at arm's length. Glass is spent on
//    the three things that are not rows — the summary, the filter tiles, the
//    pinned section headers — which is what makes those read as chrome.
//  * Rows go straight into a `ForEach` inside the `LazyVStack`, never inside a
//    wrapping container, so a section's rows stay lazily materialised.
//  * Inside a country, worth-it sorts first (`Verdict.sortRank`). The question
//    the user arrives with is "what was good in Japan", not "what was last".
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

// MARK: - Section Model
/// One run of rows under one pinned header. Country name, year, or nothing at
/// all — the row list does not care which, so all three grouping modes render
/// through the same code path.
private struct PlaceLogSection: Identifiable {
    let id: String
    /// `nil` renders no header, which is what a pure ranking wants.
    let title: String?
    let flag: String?
    let worthItCount: Int
    let summaries: [PlaceSummary]

    var placeCount: Int { summaries.count }
}

// MARK: - Log Stats
/// One pass over the log for everything the header needs, rather than five
/// separate passes over `placeSummaries`.
private struct PlaceLogStats {
    var placeCount: Int = 0
    var countryCount: Int = 0
    var yearCount: Int = 0
    /// Endpoints of the log's timeline. The card's identity line states the
    /// span; the `yearCount` column states its size. They are different facts
    /// and a log with a two-year gap in it proves they are.
    var earliestYear: Int?
    var latestYear: Int?
    var verdictCounts: [Verdict: Int] = [:]
    var unratedCount: Int = 0
}

// MARK: - Place Log View
struct PlaceLogView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var placeStore = PlaceStore.shared
    @ObservedObject private var pendingReview = PendingReviewStore.shared

    /// Optional escape hatch for the empty state. When nil the empty state
    /// renders as copy only — `PlaceLogEmptyStateView` hides a button whose
    /// action is missing.
    private let onAddTrip: (() -> Void)?

    @State private var searchText: String = ""
    @State private var verdictFilter: Verdict?
    @State private var grouping: PlaceLogGrouping = .country
    @State private var path: [Place] = []
    /// The trip whose deck is open. A library scan can find twenty trips at
    /// once; onboarding reviews one, and this is where the rest come back.
    @State private var resumeEpisode: LibraryEpisode?
    @State private var isConfirmingDiscard = false

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
        .task {
            await placeStore.syncIfNeeded()
            // After the sync, so a verdict recorded on another device retires
            // its episode here instead of being offered again.
            pendingReview.pruneDecided()
        }
        .fullScreenCover(item: $resumeEpisode) { episode in
            PlaceReviewView(
                trip: episode.asTrip(),
                detectedPlaces: pendingReview.undecidedPlaces(in: episode),
                onFinish: { _ in pendingReview.markReviewed(episode) }
            )
            // A cover is its own presentation and inherits neither the theme
            // object nor the colour scheme resolved further up.
            .environmentObject(themeManager)
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
        }
        .confirmationDialog(
            "Discard what the scan found?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { pendingReview.clear() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Finding these took a full pass over your photo library. Getting them back means running it again.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if placeStore.places.isEmpty {
            ScrollView {
                // Before the empty state, not after it. A user who scanned and
                // then judged nothing has an empty log AND a full queue, and
                // "no places yet" is the wrong first thing to read when the
                // app is holding a hundred of them.
                VStack(spacing: AppSpacing.lg) {
                    pendingReviewCard

                    PlaceLogEmptyStateView(
                        state: .noTrips,
                        onPrimaryAction: onAddTrip
                    )
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xl)
            }
            .refreshable { await placeStore.forceSync() }
            .skylineScrollEdges()
        } else {
            logScroll
        }
    }

    private var logScroll: some View {
        let stats = logStats
        let sections = self.sections

        return ScrollView {
            // spacing 0: rows must sit flush so the verdict rails form one
            // continuous column. Every non-row block pays for its own gap.
            LazyVStack(
                alignment: .leading,
                spacing: 0,
                pinnedViews: [.sectionHeaders]
            ) {
                header(stats: stats)

                if visibleSummaries.isEmpty {
                    noMatches
                } else {
                    ForEach(sections) { section in
                        Section {
                            rows(in: section)
                            Color.clear.frame(height: AppSpacing.lg)
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.xxl)
            .animation(listAnimation, value: verdictFilter)
            .animation(listAnimation, value: grouping)
            .animation(listAnimation, value: trimmedSearch.isEmpty)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await placeStore.forceSync() }
        .skylineScrollEdges()
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    // MARK: - Header

    /// Summary, then filter, then the results line. The summary is dropped the
    /// moment a filter or a query is on: it describes the whole log, and leaving
    /// it up would have it contradicting the list directly underneath it.
    @ViewBuilder
    private func header(stats: PlaceLogStats) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Outside the `isFiltering` guard: the summary is dropped while
            // filtering because it describes the log, but this describes work
            // that is not in the log at all, so a filter cannot contradict it.
            pendingReviewCard

            if !isFiltering {
                summaryCard(stats: stats)
            }

            VerdictPicker(
                selection: $verdictFilter,
                showsLabels: true,
                counts: stats.verdictCounts
            )

            if isFiltering {
                resultsBar
            }
        }
        .padding(.bottom, AppSpacing.md)
    }

    // MARK: - Resume

    /// The way back into a scan that was never finished.
    ///
    /// Detecting places over a real library is a minutes-long pass, and it
    /// routinely returns more than anyone will judge in one sitting — 120
    /// places across 21 trips on the library this was built against. Onboarding
    /// reviews the newest trip and stops, which is right; it used to then throw
    /// the other twenty away, which was not. This card is the other half of
    /// that decision.
    @ViewBuilder
    private var pendingReviewCard: some View {
        if let episode = pendingReview.nextEpisode {
            let theme = themeManager.currentTheme
            let next = pendingReview.undecidedPlaces(in: episode).count
            let trips = pendingReview.pendingEpisodes.count
            let total = pendingReview.pendingPlaceCount

            SkyLineGlassPanel(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("WAITING ON YOU")
                            .appFont(.footnote, lineLimit: .exactly(1))
                            .tracking(1.1)
                            .foregroundStyle(theme.colors.accent)

                        Text(pendingHeadline(trips: trips, places: total))
                            .appFont(.bodyBold, lineLimit: .exactly(2))
                            .foregroundStyle(theme.colors.text)

                        Text("Found in your photos. Nothing joins your log until you say so.")
                            .appFont(.footnote, lineLimit: .exactly(2))
                            .foregroundStyle(theme.colors.textSecondary)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        resumeEpisode = episode
                    } label: {
                        VStack(spacing: 2) {
                            Text(episode.title)
                                .appFont(.bodyBold, lineLimit: .exactly(1))
                            Text(next == 1 ? "1 place" : "\(next) places")
                                .appFont(.caption, lineLimit: .exactly(1))
                                .opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xs)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(theme.colors.primary)
                    .accessibilityLabel(Text("Review \(next) places in \(episode.title)"))

                    // Plain text, not a second capsule. Throwing the scan away
                    // is a real option but never the one being offered.
                    Button {
                        isConfirmingDiscard = true
                    } label: {
                        Text("Discard these")
                            .appFont(.caption, lineLimit: .exactly(1))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity)
                .skylineGlassCard(theme: theme)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func pendingHeadline(trips: Int, places: Int) -> String {
        let placeNoun = places == 1 ? "place" : "places"
        guard trips > 1 else { return "\(places) \(placeNoun) left to judge" }
        return "\(places) \(placeNoun) across \(trips) trips left to judge"
    }

    /// The log as an object: a name, three numbers, then the whole thing as one
    /// bar.
    ///
    /// The bar is also the legend. It teaches the three verdict colours in the
    /// one place the user is already looking, which is what lets the rows below
    /// carry a 3pt rail and still be read.
    private func summaryCard(stats: PlaceLogStats) -> some View {
        let theme = themeManager.currentTheme

        return SkyLineGlassPanel(spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    identityRow(stats: stats)

                    // No rules between the numbers. A vertical divider is what
                    // turns three facts into a spreadsheet, and it is furniture
                    // the numbers do not need: Strava's stat grid and
                    // Polarsteps' profile row both separate with whitespace
                    // alone. Dropping it also leaves the distribution bar below
                    // as the ONLY drawn line on the card, which is what makes
                    // that line read as the legend rather than as more chrome.
                    HStack(alignment: .top, spacing: 0) {
                        statColumn(
                            value: stats.placeCount,
                            label: stats.placeCount == 1 ? "place" : "places"
                        )
                        statColumn(
                            value: stats.countryCount,
                            label: stats.countryCount == 1 ? "country" : "countries"
                        )
                        statColumn(
                            value: stats.yearCount,
                            label: stats.yearCount == 1 ? "year" : "years"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    VerdictDistributionBar(
                        counts: stats.verdictCounts,
                        unratedCount: stats.unratedCount
                    )

                    Text(distributionCaption(stats: stats))
                        .appFont(.footnote, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity)
            .skylineGlassCard(theme: theme)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(summaryAccessibilityLabel(stats: stats)))
    }

    /// What the card IS, said out loud.
    ///
    /// Without the dividers the three numbers stop looking like a table, and a
    /// card that is no longer a table needs to name itself or it reads as three
    /// loose figures floating above a bar. This is the same move Strava makes
    /// with the badge on its summary card: one small identity element, top
    /// left, so everything under it has something to belong to.
    ///
    /// The year span rides on the right because it is the one fact the three
    /// columns underneath cannot state - `yearCount` says how many years the
    /// log covers, never which ones.
    private func identityRow(stats: PlaceLogStats) -> some View {
        let theme = themeManager.currentTheme

        return HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Text("YOUR LOG")
                .appFont(.footnote, lineLimit: .exactly(1))
                .tracking(1.1)
                .foregroundStyle(theme.colors.textSecondary)

            Spacer(minLength: AppSpacing.sm)

            if let span = yearSpanText(stats: stats) {
                Text(span)
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .accessibilityHidden(true)
    }

    /// "2026" for a single year, "2019-2026" for a run. Nil when the log has no
    /// dated place at all, which is the one case where a span would be a lie.
    private func yearSpanText(stats: PlaceLogStats) -> String? {
        guard let earliest = stats.earliestYear, let latest = stats.latestYear else { return nil }
        return earliest == latest ? "\(earliest)" : "\(earliest)\u{2013}\(latest)"
    }

    /// Spoken form of the whole card, including the identity line that is
    /// hidden from VoiceOver as a separate element.
    private func summaryAccessibilityLabel(stats: PlaceLogStats) -> String {
        var text = "Your log. \(stats.placeCount) places in \(stats.countryCount) countries across \(stats.yearCount) years"
        if let earliest = stats.earliestYear, let latest = stats.latestYear {
            text += earliest == latest ? ", \(earliest)" : ", \(earliest) to \(latest)"
        }
        return text
    }

    private func distributionCaption(stats: PlaceLogStats) -> String {
        if stats.unratedCount == 0 {
            return "EVERY PLACE HAS A VERDICT"
        }
        let noun = stats.unratedCount == 1 ? "PLACE" : "PLACES"
        return "\(stats.unratedCount) \(noun) STILL UNDECIDED"
    }

    /// Leading-aligned, not centred. With the dividers gone the columns need an
    /// edge of their own to sit on, and the card already has one: the first
    /// column lines up under "YOUR LOG" and the labels form a second baseline
    /// straight across. Centred figures in equal thirds only read as a table
    /// while something is drawn between them.
    private func statColumn(value: Int, label: String) -> some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("\(value)")
                .appFont(.title, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.text)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .appFont(.footnote, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Results Bar

    private var resultsBar: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.sm) {
            Text(resultsText)
                .appFont(.caption, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.textSecondary)

            Spacer(minLength: AppSpacing.sm)

            // A glass capsule directly beneath a row of glass verdict chips
            // ranked the reset equal to the thing it resets - same material,
            // same silhouette, one row apart. Plain type in `primary` reads as
            // the affordance it is: the way back, not a fourth filter.
            //
            // The capsule was also the hit target, so the frame has to put the
            // 44pt back explicitly. `contentShape` makes the whole 44pt tappable
            // rather than just the glyph-height text inside it.
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
                    .foregroundStyle(theme.colors.primary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Clear filters"))
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

    // MARK: - Section Header

    /// A content-hugging glass pill on an opaque band. The band is what the rows
    /// disappear behind as they scroll — glass alone over moving rows reads as a
    /// smear at this size — and it is `background`, so against the sheet slab it
    /// is invisible until it has something to cover.
    @ViewBuilder
    private func sectionHeader(_ section: PlaceLogSection) -> some View {
        if let title = section.title {
            let theme = themeManager.currentTheme

            HStack(spacing: AppSpacing.sm) {
                if let flag = section.flag {
                    Text(flag)
                        .appFont(.bodySmall, lineLimit: .exactly(1))
                }

                Text(title)
                    .appFont(.captionBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)

                Text("\(section.placeCount)")
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)

                if section.worthItCount > 0 {
                    Label("\(section.worthItCount)", systemImage: Verdict.worthIt.systemImage)
                        .labelStyle(.titleAndIcon)
                        .appFont(.footnote, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.verdictWorthIt)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .padding(.horizontal, AppSpacing.md - 2)
            .padding(.vertical, AppSpacing.sm - 2)
            .skylineGlassCapsule(theme: theme)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                theme.colors.background
                    .padding(.horizontal, -AppSpacing.md)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(sectionHeaderAccessibilityLabel(section)))
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func sectionHeaderAccessibilityLabel(_ section: PlaceLogSection) -> String {
        let noun = section.placeCount == 1 ? "place" : "places"
        var text = "\(section.title ?? ""), \(section.placeCount) \(noun)"
        if section.worthItCount > 0 {
            text += ", \(section.worthItCount) worth it"
        }
        return text
    }

    // MARK: - Rows

    /// Declared as a bare `ForEach` so `LazyVStack` keeps its laziness: wrapping
    /// a section's rows in a `VStack` would materialise every row in the section
    /// the moment its header came near the viewport.
    private func rows(in section: PlaceLogSection) -> some View {
        ForEach(Array(section.summaries.enumerated()), id: \.element.id) { index, summary in
            PlaceLogRow(
                summary: summary,
                photoIdentifier: placeStore
                    .mostRecentVisit(for: summary.place.id)?
                    .photoLocalIdentifiers
                    .first,
                showsSeparator: index < section.summaries.count - 1
            ) {
                path.append(summary.place)
            }
        }
    }

    // MARK: - No Matches
    /// A search / filter miss, which is not the same thing as an empty log:
    /// `PlaceLogEmptyStateView` owns the "you have nothing yet" story and its
    /// copy is about photos and trip dates, which would be wrong here.
    private var noMatches: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.sm) {
            Image(systemName: verdictFilter.map { $0.systemImageOutline } ?? "magnifyingglass")
                .font(AppTypography.mono(.title2))
                .foregroundStyle(
                    verdictFilter.map { $0.color(for: theme) } ?? theme.colors.textSecondary
                )
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

    /// The whole log in one pass. Called once per render of `logScroll`.
    private var logStats: PlaceLogStats {
        var stats = PlaceLogStats()
        var countries = Set<String>()
        var years = Set<Int>()
        let calendar = Calendar.current

        for summary in placeStore.placeSummaries {
            stats.placeCount += 1

            if let country = summary.place.country, !country.isEmpty {
                countries.insert(country)
            }
            years.insert(calendar.component(.year, from: PlaceLogView.effectiveDate(summary)))

            if let verdict = summary.verdict {
                stats.verdictCounts[verdict, default: 0] += 1
            } else {
                stats.unratedCount += 1
            }
        }

        stats.countryCount = countries.count
        stats.yearCount = years.count
        stats.earliestYear = years.min()
        stats.latestYear = years.max()
        return stats
    }

    // MARK: - Sections

    private var sections: [PlaceLogSection] {
        switch grouping {
        case .country: return countrySections
        case .recent: return yearSections
        case .mostVisited: return rankedSection
        }
    }

    /// Countries over the *filtered* set, so a verdict filter empties a country
    /// section instead of leaving a header with nothing under it. Ordering
    /// matches `PlaceStore.placesByCountry`: most places first, then A-Z.
    ///
    /// Inside a country the order is opinion-first — `Verdict.sortRank`, then
    /// most recent. A country section is the answer to "what should I do in
    /// Japan", and that answer is not chronological.
    private var countrySections: [PlaceLogSection] {
        let grouped = Dictionary(grouping: visibleSummaries) { summary -> String in
            let country = summary.place.country ?? ""
            return country.isEmpty ? "Unknown" : country
        }

        return grouped
            .map { countryName, summaries -> PlaceLogSection in
                let ranked = summaries.sorted(by: PlaceLogView.verdictFirst)
                return PlaceLogSection(
                    id: "country-\(countryName)",
                    title: countryName,
                    flag: PlaceLogView.flagEmoji(for: summaries.compactMap { $0.place.countryCode }.first),
                    worthItCount: summaries.filter { $0.verdict == .worthIt }.count,
                    summaries: ranked
                )
            }
            .sorted { lhs, rhs in
                if lhs.placeCount != rhs.placeCount { return lhs.placeCount > rhs.placeCount }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }
    }

    /// Years, newest first. Order inside a year is untouched — `visibleSummaries`
    /// is already most-recent-first, which is the whole point of this mode. The
    /// header is what supplies the time context the dense row drops.
    private var yearSections: [PlaceLogSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleSummaries) { summary -> Int in
            calendar.component(.year, from: PlaceLogView.effectiveDate(summary))
        }

        return grouped.keys.sorted(by: >).map { year -> PlaceLogSection in
            let summaries = grouped[year] ?? []
            return PlaceLogSection(
                id: "year-\(year)",
                title: String(year),
                flag: nil,
                worthItCount: summaries.filter { $0.verdict == .worthIt }.count,
                summaries: summaries
            )
        }
    }

    /// One unheadered run: in a ranking, the rank *is* the structure, and a
    /// header would only interrupt it.
    private var rankedSection: [PlaceLogSection] {
        let summaries = visibleSummaries
        guard !summaries.isEmpty else { return [] }

        return [
            PlaceLogSection(
                id: "most-visited",
                title: nil,
                flag: nil,
                worthItCount: summaries.filter { $0.verdict == .worthIt }.count,
                summaries: summaries
            )
        ]
    }

    /// Worth it, then Fine, then Skip, then unrated; most recent inside each.
    private static func verdictFirst(_ lhs: PlaceSummary, _ rhs: PlaceSummary) -> Bool {
        let leftRank = lhs.verdict?.sortRank ?? Verdict.allCases.count
        let rightRank = rhs.verdict?.sortRank ?? Verdict.allCases.count
        if leftRank != rightRank { return leftRank < rightRank }

        let leftDate = effectiveDate(lhs)
        let rightDate = effectiveDate(rhs)
        if leftDate != rightDate { return leftDate > rightDate }

        return lhs.place.name < rhs.place.name
    }

    /// A place with no recorded visit still has to land somewhere on a timeline;
    /// the day it entered the log is the honest stand-in.
    private static func effectiveDate(_ summary: PlaceSummary) -> Date {
        summary.lastVisitDate ?? summary.place.createdAt
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
    var showsSeparator: Bool = true
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
            style: .listRow,
            showsYear: true,
            // A place with no photograph still says what kind of thing it is.
            placeholderSystemImage: summary.place.category.systemImage,
            showsSeparator: showsSeparator,
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
