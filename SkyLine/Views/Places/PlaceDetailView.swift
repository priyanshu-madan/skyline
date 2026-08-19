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

import SwiftUI
import MapKit
import CoreLocation

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

    // MARK: Body

    var body: some View {
        let theme = themeManager.currentTheme

        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                header(theme: theme)

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

    // MARK: Header

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
    /// then says whether the verdict held or moved.
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

            Text(didChangeVerdict ? "You changed your mind" : "Same call every time")
                .appFont(.bodyBold)
                .foregroundStyle(theme.colors.text)

            if ratedVisitsOldestFirst.count > 1 {
                verdictTrajectory(theme: theme)
            }

            if !counts.isEmpty {
                // Every verdict gets a row, including the ones scoring zero, so
                // "Skip" reads as an answer the place could have had rather than
                // an absence.
                VStack(spacing: AppSpacing.xs + 2) {
                    ForEach(Verdict.allCases) { verdict in
                        verdictTallyRow(verdict: verdict, count: counts[verdict] ?? 0, theme: theme)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skylineGlassCard(theme: theme)
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
        return "Verdict history. " + steps.joined(separator: ", then ")
    }

    // MARK: Where it is

    @ViewBuilder
    private func locationCard(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionTitle("Where it is", theme: theme)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if place.hasValidCoordinate {
                    PlaceLocationMap(place: place, verdict: summary.verdict)
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

// MARK: - Location Map
/// A small, non-interactive map with one marker. Interaction is off because this
/// sits inside a vertical scroll view — a pannable map here would eat the drag.
private struct PlaceLocationMap: View {
    @EnvironmentObject var themeManager: ThemeManager

    let place: Place
    let verdict: Verdict?

    @ScaledMetric(relativeTo: .body) private var mapHeight: CGFloat = 170

    var body: some View {
        let theme = themeManager.currentTheme
        let region = MKCoordinateRegion(
            center: place.coordinate,
            latitudinalMeters: 900,
            longitudinalMeters: 900
        )

        Map(initialPosition: .region(region), interactionModes: []) {
            Marker(place.name, systemImage: place.category.systemImage, coordinate: place.coordinate)
                .tint(verdict.map { $0.color(for: theme) } ?? theme.colors.accent)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: mapHeight)
        .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
        .allowsHitTesting(false)
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

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // When
            VStack(alignment: .leading, spacing: 2) {
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

            // What you decided. Each visit owns its own verdict — going back and
            // hating it does not rewrite what you thought the first time.
            VisitVerdictRow(visit: visit)

            // What you wrote
            noteBlock(theme: theme)

            // What you shot
            if visit.hasPhotos {
                VisitPhotoStrip(identifiers: visit.photoLocalIdentifiers)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skylineGlassCard(theme: theme)
    }

    private var dayText: String {
        VisitDayFormatter.string(from: visit.date, in: timeZone)
    }

    @ViewBuilder
    private func noteBlock(theme: AppTheme) -> some View {
        if let note = visit.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(note)
                    .appFont(.body, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onEditNote) {
                    Label("Edit note", systemImage: "square.and.pencil")
                        .appFont(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.accent)
            }
            .padding(AppSpacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ConcentricRectangle(corners: .concentric, isUniform: true)
                    .fill(theme.colors.surface.opacity(0.55))
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
                                .stroke(theme.colors.border.opacity(0.6), lineWidth: 0.5)
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
