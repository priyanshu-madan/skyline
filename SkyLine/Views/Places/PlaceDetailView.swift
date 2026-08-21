//
//  PlaceDetailView.swift
//  SkyLine
//
//  One place, and everything the user knows about it.
//
//  The interesting case is the place you went back to. A single visit is a
//  footnote; four visits with three different verdicts is the whole point of
//  keeping a place log at all. So the repeat is promoted to its own card at the
//  top, and every visit below carries its own verdict and its own note — an
//  opinion is allowed to change between trips, and this screen is where that
//  change is visible and editable.
//
//  ── Why every place gets a cover ───────────────────────────────────────────
//
//  The hero used to be a binary: a photograph, or a flat run of type. But a
//  place always has a location even when it has no photograph, and the map that
//  could have been its cover was already being drawn 200pt further down this
//  same screen. So the cover is a three-step fallback — photograph, then map,
//  then type — and when the map is promoted to the cover, the duplicate lower
//  down collapses to an address and a hand-off. A map used as ground is
//  desaturated and veiled so the caption stays the loud element, and it keeps
//  the legibility gradient: the reference this comes from can set dark ink
//  straight onto a pale map, and SkyLine's ink is light.
//
//  ── Why this screen used to render DARK CARDS on a LIGHT PAGE ──────────────
//
//  Nothing in this file ever named a dark colour. The page was `colors.background`
//  and the cards were `.skylineGlassCard`. The bug was one level down: Liquid
//  Glass, `.buttonStyle(.glass)`, MapKit's tile set, `TextEditor`, and every
//  other system-drawn surface resolve their appearance from
//  `EnvironmentValues.colorScheme` — never from `themeManager.currentTheme`.
//
//  The app only ever expressed its theme through `.preferredColorScheme(...)`
//  (SkyLineApp:97, ContentView:72). That is a *preference*: it travels up to the
//  nearest hosting controller and is re-applied at that presentation's root. It
//  does not reliably reach a `navigationDestination` subtree living inside a
//  sheet that has `.presentationBackground(.clear)` — which is exactly where
//  this view lives (globe sheet → SkyLineBottomBarView → PlaceLogView's
//  NavigationStack → here). So on a dark-appearance device with the app's Light
//  theme selected, `colors.background` correctly painted a light page while the
//  glass above it, and the map inside it, still rendered in the *device's* dark
//  scheme. Dark cards, light page. Same class of bug as the one already fixed
//  inside Theme.swift, one layer further out.
//
//  The fix is to stop hinting and start stating: every screen root in this file
//  writes the app theme straight into the environment with
//  `.environment(\.colorScheme, theme.colorScheme)`. That is a value, not a
//  preference, so it propagates down the whole subtree unconditionally and takes
//  the glass, the map and the text editor with it. Patching a single fill would
//  have left the map, the `.glass` buttons and the keyboard still wrong.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - On-Cover Ink
/// A hero cover carries its own light: a photograph, or a map under a scrim, is
/// a dark-mode context no matter which theme the app is in, so the caption over
/// one must not flip with the theme.
///
/// These are still tokens — they are the dark palette, pinned deliberately —
/// rather than `Color.white` / `Color.black` literals, so an audit stays
/// mechanical and a palette change still moves them.
private enum PhotoInk {
    static let primary = ThemeColors.dark.text
    static let scrim = ThemeColors.dark.background
}

// MARK: - Hero Metrics
private enum HeroMetrics {
    /// Ground, not subject. A map that reads as a picture of a map competes with
    /// the name set on top of it.
    static let mapSaturation: Double = 0.35

    /// `saturation` is a rendering filter, and a `Map` is a platform view rather
    /// than something SwiftUI draws itself — so the filter is asked for, and then
    /// a veil in the theme's own ground colour does the muting that does not
    /// depend on the filter having landed. Both push the tiles the same way:
    /// toward the page in light, into the night in dark.
    static let mapVeilOpacity: Double = 0.22

    /// The card lower down wants the street; a cover wants the neighbourhood,
    /// because a cover reads as a place rather than as a pin.
    static let mapSpanMeters: CLLocationDistance = 2000

    /// Roughly six lines of body copy. Past this a note fades out rather than
    /// pushing the visit below it off the screen.
    static let collapsedNoteHeight: CGFloat = 132
}

// MARK: - Formatters
private extension DateFormatter {
    /// "Mar 2026" — the span in the repeat card and the labels on the verdict
    /// trajectory. Never mutated, so one shared instance is safe.
    static let placeDetailMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()
}

/// "Sat, 14 Mar 2026" in the *place's* time zone, not the reader's.
///
/// A photo taken at 1am in Tokyo belongs to that night in Tokyo, not to the
/// previous afternoon in California, and a travel log that disagrees with the
/// user's memory of which day they went is worse than useless. The formatter is
/// cached per time zone rather than reconfigured in place: mutating one shared
/// `DateFormatter.timeZone` from several cards is exactly the kind of shared
/// mutable state that renders the wrong date once two places are on screen.
@MainActor
private enum VisitDayFormatter {
    private static var cache: [String: DateFormatter] = [:]

    static func string(from date: Date, in timeZone: TimeZone) -> String {
        let formatter: DateFormatter
        if let cached = cache[timeZone.identifier] {
            formatter = cached
        } else {
            let made = DateFormatter()
            made.dateFormat = "EEE, d MMM yyyy"
            made.timeZone = timeZone
            cache[timeZone.identifier] = made
            formatter = made
        }
        return formatter.string(from: date)
    }
}

// MARK: - Place Detail
struct PlaceDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var placeStore = PlaceStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The place is looked up by id on every render so an edit made elsewhere
    /// (a rename, a merge) shows up here. `seedPlace` is the copy handed to the
    /// initializer and is only used until the store has one — and as the
    /// fallback if the place is deleted while this screen is on top.
    private let placeId: String
    private let seedPlace: Place

    @State private var noteEditorVisit: Visit?

    /// Roughly 4:3 on a 390pt-wide device. `@ScaledMetric` rather than a constant
    /// so the picture grows with the caption sitting on it instead of the caption
    /// outgrowing the frame at accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 260

    init(place: Place) {
        self.placeId = place.id
        self.seedPlace = place
    }

    // MARK: Derived state

    private var place: Place {
        placeStore.place(by: placeId) ?? seedPlace
    }

    /// Newest first. This is the order the screen reads in.
    private var visits: [Visit] {
        placeStore.visits(for: placeId).sortedByDateDescending()
    }

    private var summary: PlaceSummary {
        PlaceSummary(place: place, visits: visits)
    }

    private var ratedVisitsOldestFirst: [Visit] {
        visits.filter { $0.verdict != nil }.sortedByDateAscending()
    }

    /// True when the user rated this place more than once and did not say the
    /// same thing every time. The single most interesting fact on this screen.
    private var didChangeVerdict: Bool {
        let verdicts = ratedVisitsOldestFirst.compactMap { $0.verdict }
        guard verdicts.count > 1 else { return false }
        return Set(verdicts).count > 1
    }

    /// The photograph this place gets to lead with: the first frame of the most
    /// recent visit that actually shot anything. A place the user photographed
    /// is a place they remember looking at, so the picture outranks the label.
    private var heroAssetIdentifier: String? {
        visits.first { !$0.photoLocalIdentifiers.isEmpty }?.photoLocalIdentifiers.first
    }

    // MARK: Body

    var body: some View {
        let theme = themeManager.currentTheme

        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                hero(theme: theme)

                if visits.count > 1 {
                    repeatCard(theme: theme)
                }

                locationCard(theme: theme)

                visitsSection(theme: theme)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xxl)
            // The repeat card appears the moment a second visit lands, which
            // reflows everything under it. Ease that, unless the user has asked
            // the system not to move things around.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: visits.count)
        }
        .skylineScrollEdges()
        .background(theme.colors.background.ignoresSafeArea())
        // See the file header. This is the fix for "dark cards on a light page":
        // the glass, the MapKit tile set and the note editor all read the
        // environment's colour scheme, and until this line they were reading the
        // device's rather than the app's.
        .environment(\.colorScheme, theme.colorScheme)
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The nav bar is already Liquid Glass on iOS 26 — the background is
            // deliberately not hidden here so this button sits in that glass.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openInAppleMaps(withDirections: true)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                }
                .disabled(!place.hasValidCoordinate)
            }
        }
        .sheet(item: $noteEditorVisit) { visit in
            VisitNoteEditor(visit: visit, placeName: place.name, timeZone: place.timeZone) { newNote in
                Task {
                    _ = await placeStore.updateVisit(visit.with(note: newNote))
                }
            }
            .environmentObject(themeManager)
        }
    }

    // MARK: Hero

    /// What this place gets to lead with.
    ///
    /// Three steps, not two. A photograph is the best cover because it is what
    /// the user chose to look at; failing that the map is a cover, because
    /// location is the one asset a place never lacks; only a place with neither
    /// falls through to type.
    private enum HeroCover {
        case photo(String)
        case map
        case type
    }

    private var heroCover: HeroCover {
        if let heroAssetIdentifier { return .photo(heroAssetIdentifier) }
        if place.hasValidCoordinate { return .map }
        return .type
    }

    /// True when the map has been promoted to the cover, and so must not also be
    /// drawn as a card further down the same screen.
    private var heroIsMap: Bool {
        if case .map = heroCover { return true }
        return false
    }

    @ViewBuilder
    private func hero(theme: AppTheme) -> some View {
        switch heroCover {
        case .photo(let assetIdentifier):
            heroCard(theme: theme) {
                PHAssetImageView(
                    localIdentifier: assetIdentifier,
                    size: .card,
                    contentMode: .fill
                )
            }
        case .map:
            heroCard(theme: theme) {
                PlaceMapCanvas(
                    place: place,
                    verdict: summary.verdict,
                    spanMeters: HeroMetrics.mapSpanMeters
                )
                .saturation(HeroMetrics.mapSaturation)
                .overlay {
                    theme.colors.background.opacity(HeroMetrics.mapVeilOpacity)
                }
                // The caption already names the place, and the badge already
                // states the verdict; a second "map showing…" inside the
                // combined element would only be read out twice.
                .accessibilityHidden(true)
            }
        case .type:
            header(theme: theme)
        }
    }

    /// One hero, two possible covers. Same construction as a deck card — cover
    /// clipped into a concentric rectangle, legibility gradient, caption laid
    /// over the bottom third, glass frame — so a place looks like the same
    /// object on the screen where it was judged and the screen where it is
    /// remembered, and an unphotographed place looks like a place rather than
    /// like a gap.
    @ViewBuilder
    private func heroCard<Cover: View>(
        theme: AppTheme,
        @ViewBuilder cover: () -> Cover
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            cover()
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity)
                // Gradient BEFORE the clip. An overlay applied after a clip is
                // not itself clipped, and this one ends at 0.82 opacity — so it
                // used to paint two square navy corners across the bottom of a
                // rounded cover.
                .overlay { photoLegibilityGradient }
                .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))

            heroCaption(theme: theme)
        }
        .padding(AppSpacing.xs)
        .skylineGlassCard(theme: theme)
        .overlay(alignment: .topTrailing) {
            heroVerdict(theme: theme)
                .padding(AppSpacing.sm + 2)
        }
        .accessibilityElement(children: .combine)
    }

    /// The plinth: identical over a photograph and over a map, because the ink
    /// is pinned to the dark palette in both cases and the gradient guarantees
    /// the ground under it.
    @ViewBuilder
    private func heroCaption(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(place.category.displayName.uppercased())
                .appFont(.footnote)
                .foregroundStyle(PhotoInk.primary.opacity(0.75))
                .accessibilityLabel(Text(place.category.displayName))

            Text(place.name)
                .appFont(.title, lineLimit: .exactly(2))
                .foregroundStyle(PhotoInk.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Locality and visit count share one baseline rather than the
            // count floating in a corner overlay, so a long city name
            // cannot slide underneath it.
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                if !place.displayLocality.isEmpty {
                    Text(place.displayLocality)
                        .appFont(.placeMeta, lineLimit: .exactly(1))
                        .foregroundStyle(PhotoInk.primary.opacity(0.85))
                }

                Spacer(minLength: AppSpacing.sm)

                Text(summary.visitCountText)
                    .appFont(.verdictLabel)
                    .foregroundStyle(PhotoInk.primary.opacity(0.85))
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func heroVerdict(theme: AppTheme) -> some View {
        if let verdict = summary.verdict {
            VerdictBadge(verdict: verdict)
        } else {
            Text("NOT RATED")
                .appFont(.verdictLabel)
                .foregroundStyle(theme.colors.text)
                .padding(.horizontal, AppSpacing.sm + 2)
                .padding(.vertical, 5)
                .skylineGlassCapsule(theme: theme)
        }
    }

    /// A photograph cannot be relied on for contrast, and glass behind it cannot
    /// help — the picture is on top. This is the contrast floor for the caption,
    /// and the map cover keeps it: the reference that sets dark ink straight
    /// onto an unscrimmed map can do that because its map is pale and its ink is
    /// dark. Both of those are the other way round here.
    private var photoLegibilityGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.30),
                .init(color: PhotoInk.scrim.opacity(0.32), location: 0.58),
                .init(color: PhotoInk.scrim.opacity(0.82), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    // MARK: Header

    /// The third fallback: no photograph AND no coordinate, so there is no cover
    /// to be had. Type only, and the name gets to be the biggest thing on the
    /// screen instead.
    @ViewBuilder
    private func header(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs + 2) {
                Image(systemName: place.category.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.colors.textSecondary)
                Text(place.category.displayName.uppercased())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .appFont(.footnote)
            .accessibilityLabel(Text(place.category.displayName))

            // The large title. `appFont` bundles the shrink-to-fit rules, so a
            // long name on a 375pt screen scales instead of truncating.
            Text(place.name)
                .appFont(.titleLarge, lineLimit: .exactly(3))
                .foregroundStyle(theme.colors.text)
                .fixedSize(horizontal: false, vertical: true)

            if !place.displayLocality.isEmpty {
                Text(place.displayLocality)
                    .appFont(.placeMeta)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            HStack(spacing: AppSpacing.sm) {
                if let verdict = summary.verdict {
                    VerdictBadge(verdict: verdict)
                } else {
                    Text("NOT RATED")
                        .appFont(.verdictLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, AppSpacing.sm + 2)
                        .padding(.vertical, 5)
                        .skylineGlassCapsule(theme: theme)
                }

                Text(summary.visitCountText)
                    .appFont(.placeMeta)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(.top, AppSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The repeat

    /// Only rendered for places visited more than once. Leads with the count,
    /// then states how the verdict moved and across how many visits it moved.
    @ViewBuilder
    private func repeatCard(theme: AppTheme) -> some View {
        let counts = summary.verdictCounts

        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text("\(visits.count)")
                    .appFont(.title)
                    .foregroundStyle(theme.colors.text)
                Text("visits")
                    .appFont(.placeMeta)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer(minLength: 0)
                Text(visitSpanText)
                    .appFont(.placeMeta)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .accessibilityElement(children: .combine)

            Text(verdictMovementText)
                .appFont(.bodyBold, lineLimit: .unlimited)
                .foregroundStyle(theme.colors.text)
                .fixedSize(horizontal: false, vertical: true)

            if ratedVisitsOldestFirst.count > 1 {
                verdictTrajectory(theme: theme)
            }

            if !counts.isEmpty {
                // The split, before the numbers. One hairline answers "what did
                // this place mostly get?" faster than three rows of counts, and
                // the unrated remainder is a segment rather than a gap so the
                // bar always accounts for every visit.
                VerdictDistributionBar(
                    counts: counts,
                    unratedCount: max(0, visits.count - counts.values.reduce(0, +))
                )

                // Every verdict still gets a row, including the ones scoring
                // zero, so "Skip" reads as an answer the place could have had
                // rather than an absence.
                VStack(spacing: AppSpacing.xs + 2) {
                    ForEach(Verdict.allCases) { verdict in
                        verdictTallyRow(verdict: verdict, count: counts[verdict] ?? 0, theme: theme)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tinted only when the verdict actually held. If the user changed their
        // mind there is no single colour that is true of this place, and picking
        // one would be the card telling a lie in the loudest ink available.
        .skylineGlassCard(
            tint: didChangeVerdict ? nil : summary.verdict.map { $0.color(for: theme).opacity(0.16) },
            theme: theme
        )
    }

    /// How the opinion moved, and what it moved across.
    ///
    /// "You changed your mind" states a movement with no base under it, and a
    /// swing from Worth it to Skip is a different fact over two visits than over
    /// six. The badges below carry the base only if the reader stops and counts
    /// them, so the sentence carries it instead — and it names the endpoints,
    /// which is the part of the trajectory worth reading at a glance.
    private var verdictMovementText: String {
        let rated = ratedVisitsOldestFirst.compactMap { $0.verdict }

        guard let first = rated.first, let last = rated.last, rated.count > 1 else {
            // One rated visit (or none) among several: there is no trajectory to
            // describe, only a repeat.
            return didChangeVerdict ? "You changed your mind" : "Same call every time"
        }

        let base = "\(rated.count) visits"

        guard didChangeVerdict else {
            return "Same call across \(base)"
        }

        // A verdict that left and came back is still a change, but
        // "Worth it to Worth it" is not a sentence.
        if first == last {
            return "Back to \(last.displayName) after \(base)"
        }

        return "\(first.displayName) to \(last.displayName) over \(base)"
    }

    /// Oldest rated verdict on the left, newest on the right.
    @ViewBuilder
    private func verdictTrajectory(theme: AppTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(Array(ratedVisitsOldestFirst.enumerated()), id: \.element.id) { index, visit in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .appFont(.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    if let verdict = visit.verdict {
                        VStack(spacing: 2) {
                            VerdictBadge(verdict: verdict, showsLabel: false, size: .compact)
                            Text(DateFormatter.placeDetailMonthYear.string(from: visit.date))
                                .appFont(.footnote)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(trajectoryAccessibilityLabel))
    }

    @ViewBuilder
    private func verdictTallyRow(verdict: Verdict, count: Int, theme: AppTheme) -> some View {
        let ink = verdict.color(for: theme)
        let isPresent = count > 0

        HStack(spacing: AppSpacing.sm) {
            Image(systemName: isPresent ? verdict.systemImage : verdict.systemImageOutline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPresent ? ink : theme.colors.textSecondary)
                .imageScale(.small)

            Text(verdict.displayName)
                .appFont(.placeMeta)
                .foregroundStyle(isPresent ? theme.colors.text : theme.colors.textSecondary)

            Spacer(minLength: AppSpacing.sm)

            Text(count == 1 ? "1 time" : "\(count) times")
                .appFont(.placeMeta)
                .foregroundStyle(isPresent ? theme.colors.text : theme.colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var visitSpanText: String {
        guard let first = summary.firstVisitDate, let last = summary.lastVisitDate else { return "" }
        let firstText = DateFormatter.placeDetailMonthYear.string(from: first)
        let lastText = DateFormatter.placeDetailMonthYear.string(from: last)
        return firstText == lastText ? firstText : "\(firstText) – \(lastText)"
    }

    private var trajectoryAccessibilityLabel: String {
        let steps = ratedVisitsOldestFirst.compactMap { visit -> String? in
            guard let verdict = visit.verdict else { return nil }
            return "\(DateFormatter.placeDetailMonthYear.string(from: visit.date)): \(verdict.displayName)"
        }
        let base = steps.count == 1 ? "1 visit" : "\(steps.count) visits"
        return "Verdict history across \(base). " + steps.joined(separator: ", then ")
    }

    // MARK: Where it is

    @ViewBuilder
    private func locationCard(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionTitle("Where it is", theme: theme)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if place.hasValidCoordinate {
                    // When the map has been promoted to the cover, drawing it
                    // again 300pt lower is the same asset twice on one screen.
                    // The card keeps the address and the hand-off, which are the
                    // parts the cover cannot carry.
                    if !heroIsMap {
                        PlaceLocationMap(place: place, verdict: summary.verdict)
                    }
                } else {
                    // Photo-derived places can land without usable coordinates.
                    // Say so rather than dropping a marker on Null Island.
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "mappin.slash")
                            .foregroundStyle(theme.colors.textSecondary)
                        Text("No location recorded for this place")
                            .appFont(.placeMeta)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.md)
                }

                Text(place.displayAddress)
                    .appFont(.placeMeta, lineLimit: .exactly(2))
                    .foregroundStyle(theme.colors.textSecondary)

                Button {
                    openInAppleMaps(withDirections: false)
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                        .appFont(.captionBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xs + 2)
                }
                .buttonStyle(.glass)
                .disabled(!place.hasValidCoordinate)
            }
            .padding(AppSpacing.glassInset)
            .skylineGlassCard(theme: theme)
        }
    }

    // MARK: Visits

    @ViewBuilder
    private func visitsSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionTitle("Visits", theme: theme)

            if visits.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("No visits recorded")
                        .appFont(.bodyBold)
                        .foregroundStyle(theme.colors.text)
                    Text("This place is on your map, but nothing has been logged against it yet.")
                        .appFont(.placeMeta, lineLimit: .unlimited)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.md)
                .skylineGlassCard(theme: theme)
            } else {
                LazyVStack(spacing: AppSpacing.md) {
                    ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                        VisitCard(
                            visit: visit,
                            ordinalLabel: ordinalLabel(forIndex: index, total: visits.count),
                            timeZone: place.timeZone,
                            onEditNote: { noteEditorVisit = visit }
                        )
                    }
                }
            }
        }
    }

    private func ordinalLabel(forIndex index: Int, total: Int) -> String {
        if total == 1 { return "Only visit" }
        if index == 0 { return "Latest visit" }
        // visits are newest-first, so the oldest is number 1.
        return "Visit \(total - index)"
    }

    @ViewBuilder
    private func sectionTitle(_ text: String, theme: AppTheme) -> some View {
        Text(text.uppercased())
            .appFont(.verdictLabel)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.leading, AppSpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Apple Maps hand-off

    private func openInAppleMaps(withDirections: Bool) {
        guard place.hasValidCoordinate else {
            print("⚠️ PlaceDetailView: no valid coordinate for \(place.name), not opening Maps")
            return
        }

        // iOS 26 deprecated MKPlacemark — MKMapItem takes a location + MKAddress now.
        let address = MKAddress(
            fullAddress: place.displayAddress,
            shortAddress: place.city
        )
        let mapItem = MKMapItem(location: place.location, address: address)
        mapItem.name = place.name

        if withDirections {
            _ = mapItem.openInMaps(
                launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault]
            )
        } else {
            _ = mapItem.openInMaps()
        }
    }
}

// MARK: - Map Canvas
/// The tiles themselves: no frame, no clip, no label of its own, so the same map
/// can be a 170pt card lower down the screen and a 260pt cover at the top of it
/// without either one owning the other's geometry.
///
/// Interaction is off because both callers sit inside a vertical scroll view —
/// a pannable map here would eat the drag.
private struct PlaceMapCanvas: View {
    @EnvironmentObject var themeManager: ThemeManager

    let place: Place
    let verdict: Verdict?
    /// Vertical extent of the visible region.
    var spanMeters: CLLocationDistance = 900

    var body: some View {
        let theme = themeManager.currentTheme
        let region = MKCoordinateRegion(
            center: place.coordinate,
            latitudinalMeters: spanMeters,
            longitudinalMeters: spanMeters
        )

        Map(initialPosition: .region(region), interactionModes: []) {
            Marker(place.name, systemImage: place.category.systemImage, coordinate: place.coordinate)
                .tint(verdict.map { $0.color(for: theme) } ?? theme.colors.accent)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
    }
}

// MARK: - Location Map
/// A small, non-interactive map with one marker, for the "Where it is" card.
/// Only rendered when the hero is NOT already a map.
private struct PlaceLocationMap: View {
    let place: Place
    let verdict: Verdict?

    @ScaledMetric(relativeTo: .body) private var mapHeight: CGFloat = 170

    var body: some View {
        PlaceMapCanvas(place: place, verdict: verdict)
            .frame(height: mapHeight)
            .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Map showing \(place.name)"))
    }
}

// MARK: - Visit Card
/// One visit: when it was, what you decided, what you wrote, what you shot.
private struct VisitCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    let visit: Visit
    let ordinalLabel: String
    let timeZone: TimeZone
    let onEditNote: () -> Void

    /// The height the note WOULD take if nothing capped it. Measured on the
    /// uncapped text, so applying the cap cannot change it and the two cannot
    /// chase each other.
    @State private var fullNoteHeight: CGFloat = 0

    /// The window the note is allowed. `@ScaledMetric` so the window grows with
    /// the type rather than swallowing more of the note at every size.
    @ScaledMetric(relativeTo: .body) private var collapsedNoteHeight: CGFloat = HeroMetrics.collapsedNoteHeight

    private var isNoteTruncated: Bool {
        fullNoteHeight > collapsedNoteHeight + 1
    }

    var body: some View {
        let theme = themeManager.currentTheme

        HStack(alignment: .top, spacing: AppSpacing.md - 4) {
            // The same spine as every other place row in the app, so a column of
            // visits reads as a column of judgements before a word is read.
            VerdictRail(verdict: visit.verdict)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // When
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(ordinalLabel.uppercased())
                            .appFont(.footnote)
                            .foregroundStyle(theme.colors.textSecondary)

                        Spacer(minLength: 0)

                        Text(visit.source.displayName)
                            .appFont(.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                    }

                    Text(dayText)
                        .appFont(.placeName, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.text)
                }
                .accessibilityElement(children: .combine)

                // What you decided. Each visit owns its own verdict — going back
                // and hating it does not rewrite what you thought the first time.
                VisitVerdictRow(visit: visit)

                // What you wrote
                noteBlock(theme: theme)

                // What you shot
                if visit.hasPhotos {
                    VisitPhotoStrip(identifiers: visit.photoLocalIdentifiers)
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skylineGlassCard(theme: theme)
    }

    private var dayText: String {
        VisitDayFormatter.string(from: visit.date, in: timeZone)
    }

    /// A long note is capped by a fade, never by an ellipsis.
    ///
    /// A fade says "there is more"; an ellipsis says "we cut this" — and a
    /// monospaced ellipsis is three characters at a fixed advance, which at this
    /// size is a visible stutter at the end of a sentence. Nothing is truncated
    /// in the accessibility tree either: the `Text` still holds the whole note,
    /// so VoiceOver reads it in full and only the drawing is masked.
    @ViewBuilder
    private func noteText(_ note: String, theme: AppTheme) -> some View {
        Text(note)
            .appFont(.body, lineLimit: .unlimited)
            .foregroundStyle(theme.colors.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                fullNoteHeight = height
            }
            // `fixedSize` above means the text keeps its full height whatever is
            // proposed, so the cap has to clip rather than compress.
            .frame(maxHeight: isNoteTruncated ? collapsedNoteHeight : nil, alignment: .top)
            .clipped()
            .mask(alignment: .top) { noteFade(theme: theme) }
    }

    /// A mask reads ALPHA only — the colour is irrelevant, so it is taken from a
    /// token rather than written as a `Color.black` literal, which keeps a
    /// colour audit of this file mechanical.
    private func noteFade(theme: AppTheme) -> LinearGradient {
        let ink = theme.colors.text
        // 0.73 of a 132pt window is the last ~36pt: about one and a half lines
        // of body copy, enough for the fall-off to read as deliberate rather
        // than as a rendering glitch.
        let stops: [Gradient.Stop] = isNoteTruncated
            ? [
                .init(color: ink, location: 0.0),
                .init(color: ink, location: 0.73),
                .init(color: ink.opacity(0), location: 1.0)
              ]
            : [
                .init(color: ink, location: 0.0),
                .init(color: ink, location: 1.0)
              ]

        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder
    private func noteBlock(theme: AppTheme) -> some View {
        if let note = visit.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                noteText(note, theme: theme)

                Button(action: onEditNote) {
                    Label(isNoteTruncated ? "Read and edit" : "Edit note", systemImage: "square.and.pencil")
                        .appFont(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.accent)
            }
            .padding(AppSpacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Material as taxonomy. Everything else on this card is generated —
            // a date, a source, a verdict, a photo count — and the note is the
            // one thing on the screen a person actually wrote. Rendering it in
            // the same glass as four derived facts said they were the same class
            // of thing. `noteSurface` is warm where the whole app is cool, so
            // the user's own writing is findable before it is read; `accent`
            // draws the edge of the page it is written on.
            .background {
                ConcentricRectangle(corners: .concentric, isUniform: true)
                    .fill(theme.colors.noteSurface)
            }
            .overlay {
                ConcentricRectangle(corners: .concentric, isUniform: true)
                    .stroke(theme.colors.accent.opacity(0.6), lineWidth: 1)
            }
        } else {
            Button(action: onEditNote) {
                Label("Add a note", systemImage: "square.and.pencil")
                    .appFont(.captionBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xs + 2)
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: - Per-Visit Verdict
/// Reuses `VerdictPicker` and writes every change straight through to the store.
/// Local `@State` mirrors the visit so the chip animates immediately; the store
/// is the source of truth and pushes back down through `onChange`.
private struct VisitVerdictRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var placeStore = PlaceStore.shared

    let visit: Visit

    @State private var selection: Verdict?
    @State private var hasLoaded = false

    var body: some View {
        VerdictPicker(selection: $selection, showsLabels: true)
            .onAppear {
                selection = visit.verdict
                hasLoaded = true
            }
            .onChange(of: visit.verdict) { _, newValue in
                guard selection != newValue else { return }
                selection = newValue
            }
            .onChange(of: selection) { _, newValue in
                guard hasLoaded, newValue != visit.verdict else { return }
                Task {
                    let result = await placeStore.setVerdict(newValue, forVisit: visit.id)
                    if case .failure(let error) = result {
                        print("❌ PlaceDetailView: verdict write failed for \(visit.id): \(error)")
                    }
                }
            }
    }
}

// MARK: - Photo Strip
/// Horizontal thumbnails for the visit's assets.
///
/// `PHAssetImageView` already degrades to a placeholder when the identifier no
/// longer resolves — deleted photo, or a limited-access selection the user has
/// since narrowed — so a missing asset costs one grey tile, never a crash. The
/// only thing added here is de-duplication of identifiers, because a repeated
/// id inside `ForEach(id: \.self)` makes SwiftUI drop rows.
private struct VisitPhotoStrip: View {
    @EnvironmentObject var themeManager: ThemeManager

    let identifiers: [String]

    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 92

    private var uniqueIdentifiers: [String] {
        var seen = Set<String>()
        return identifiers.filter { seen.insert($0).inserted }
    }

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: AppSpacing.xs + 2) {
            Text(uniqueIdentifiers.count == 1 ? "1 photo" : "\(uniqueIdentifiers.count) photos")
                .appFont(.footnote)
                .foregroundStyle(theme.colors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(uniqueIdentifiers, id: \.self) { identifier in
                        PHAssetImageView(
                            localIdentifier: identifier,
                            size: .thumbnail,
                            contentMode: .fill
                        )
                        .frame(width: thumbnailSize, height: thumbnailSize)
                        .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
                        .overlay {
                            ConcentricRectangle(corners: .concentric, isUniform: true)
                                .stroke(theme.colors.border, lineWidth: 1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(uniqueIdentifiers.count) photos from this visit"))
        }
    }
}

// MARK: - Note Editor
private struct VisitNoteEditor: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    let visit: Visit
    let placeName: String
    let timeZone: TimeZone
    let onSave: (String?) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(visit: Visit, placeName: String, timeZone: TimeZone, onSave: @escaping (String?) -> Void) {
        self.visit = visit
        self.placeName = placeName
        self.timeZone = timeZone
        self.onSave = onSave
        _draft = State(initialValue: visit.note ?? "")
    }

    var body: some View {
        let theme = themeManager.currentTheme

        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(VisitDayFormatter.string(from: visit.date, in: timeZone))
                    .appFont(.placeMeta)
                    .foregroundStyle(theme.colors.textSecondary)

                TextEditor(text: $draft)
                    .appFont(.body, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.text)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        ConcentricRectangle(corners: .fixed(AppRadius.lg), isUniform: true)
                            .fill(theme.colors.surface)
                    }
                    .overlay {
                        ConcentricRectangle(corners: .fixed(AppRadius.lg), isUniform: true)
                            .stroke(theme.colors.border, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("What do you want to remember about \(placeName)?")
                                .appFont(.body, lineLimit: .unlimited)
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(AppSpacing.sm + 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(AppSpacing.md)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        // A sheet is its own presentation, so it does not inherit the colour
        // scheme resolved for the screen that pushed it. Restate the theme here
        // or the editor's well, its caret and its keyboard follow the device.
        .environment(\.colorScheme, theme.colorScheme)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(AppRadius.sheet)
        .onAppear { isFocused = true }
    }
}

// MARK: - Previews
#Preview("Repeat visit") {
    NavigationStack {
        PlaceDetailView(
            place: Place(
                name: "Fuglen Tokyo",
                latitude: 35.6666,
                longitude: 139.6959,
                category: .cafe,
                city: "Shibuya",
                country: "Japan",
                countryCode: "JP"
            )
        )
    }
    .environmentObject(ThemeManager())
}
