//
//  SkyLineBottomBarView.swift
//  SkyLine
//
//  Bottom bar view replicating FindMyBottomBar structure
//

import SwiftUI
import PhotosUI
import CoreLocation

enum FlightNavigationContext {
    case flights        // Navigated from flights tab
    case trip(Trip)     // Navigated from a specific trip
}

enum FlightFilter: String, CaseIterable {
    case upcoming = "Upcoming"
    case past = "Past"
}

// MARK: - DateFormatter Extensions
extension DateFormatter {
    static let flightCardDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter
    }()
    
    static let flightTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    static let flightTimeArrival: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

/// Tab Enum for SkyLine
///
/// SCOPED TO BOARDING PASSES. The app is back to its original idea — scan a
/// boarding pass, store the flight, draw its path on the globe — so Flights is
/// the product surface and it is the launch tab. Profile stays because settings
/// and sign-out live there.
///
/// Places and Trips are HIDDEN AND INERT, not removed: every case, view and
/// service behind them is still here and still compiles. `barTabs` below is the
/// single switch — it decides which surfaces get a bar slot, which pages the
/// TabView builds at all, and where a request for a slot-less surface lands.
///
/// TO RESTORE: put `.places` and `.trips` back into `barTabs`. Nothing else in
/// this file needs changing; the page gating, `barRepresentative`, the default
/// tab and the Trips back-chevron are all derived from that one array.
enum SkyLineTab: String, CaseIterable {
    case places = "Places"
    case trips = "Trips"
    case flights = "Flights"
    case profile = "Profile"

    /// The tabs that get a slot in the bar, and — because everything else is
    /// derived from it — the tabs that exist at all. Scoped to boarding passes:
    /// `places` and `trips` are deliberately absent. Was `[.places, .trips, .profile]`.
    static let barTabs: [SkyLineTab] = [.flights, .profile]

    /// The surface the app opens on, and where a request for a hidden surface
    /// lands. Always a member of `barTabs`.
    static var primary: SkyLineTab { barTabs.first ?? .flights }

    /// Where a request to show `self` should actually go. A surface with no bar
    /// slot is disabled for now, so it falls back to the primary surface rather
    /// than selecting a page the TabView is not building.
    var resolved: SkyLineTab {
        SkyLineTab.barTabs.contains(self) ? self : SkyLineTab.primary
    }

    /// The bar slot that should read as selected while this surface is showing.
    ///
    /// A surface with a slot lights its own. A slot-less one lights the slot of
    /// whatever it is a sub-surface of: Flights used to hang off Trips, so when
    /// Trips has a slot it still does — which is what makes reverting `barTabs`
    /// restore the previous behaviour here for free.
    var barRepresentative: SkyLineTab {
        guard !SkyLineTab.barTabs.contains(self) else { return self }
        return SkyLineTab.barTabs.contains(.trips) ? .trips : SkyLineTab.primary
    }

    var symbolImage: String {
        switch self {
        case .places:
            return "mappin.and.ellipse"
        case .trips:
            return "suitcase"
        case .flights:
            return "airplane"
        case .profile:
            return "person.crop.circle"
        }
    }
}

struct SkyLineBottomBarView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var tripStore = TripStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabSelectionNamespace
    @State private var addTripView: Bool = false
    @State private var refreshID = UUID()
    @State private var selectedFlightId: String? = nil
    @State private var selectedFlightForDetails: Flight? = nil
    @State private var flightDetailsViewKey: UUID = UUID()
    @State private var flightNavigationContext: FlightNavigationContext = .flights
    @State private var tripToReopen: Trip? = nil
    @State private var selectedFlightFilter: FlightFilter = .upcoming
    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var profileImage: UIImage? = nil

    // Non-text metrics seeded from `AppTypography.Metrics`, so glyph wells and
    // avatars grow in step with the type beside them instead of staying frozen
    // while the labels around them get bigger.
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var avatarBadge: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var passGlyphWell: CGFloat = 44
    @ScaledMetric(relativeTo: .largeTitle) private var passWatermarkSize: CGFloat = 148
    @ScaledMetric(relativeTo: .body) private var passNotchSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var barcodeHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var statusDotSize: CGFloat = 6

    /// The surface on screen, owned by `ContentView`.
    ///
    /// It has to live up there now: the bar is in ContentView's ZStack over the
    /// globe and this sheet holds the page, so both of them read this one value.
    /// Writing it from inside — `openFlights()`, a flight tapped in a trip —
    /// changes the page AND relights the bar's slot without a second channel.
    /// There used to be an `onTabChanged` callback for exactly that; the binding
    /// replaces it, and cannot go stale the way two copies could.
    @Binding var activeTab: SkyLineTab
    @Binding var selectedDetent: PresentationDetent

    // Callbacks to communicate with parent ContentView
    let onFlightSelected: ((Flight) -> Void)?
    /// "Open the sheet for this surface." Takes the tab EXPLICITLY rather than
    /// letting ContentView re-read `activeTab`: the binding is written in the
    /// same update, and a reader in that update is not guaranteed to see it.
    let onTabSelected: ((SkyLineTab) -> Void)?
    let onGlobeReset: (() -> Void)?

    init(
        activeTab: Binding<SkyLineTab>,
        selectedDetent: Binding<PresentationDetent>,
        onFlightSelected: ((Flight) -> Void)? = nil,
        onTabSelected: ((SkyLineTab) -> Void)? = nil,
        onGlobeReset: (() -> Void)? = nil
    ) {
        self._activeTab = activeTab
        self._selectedDetent = selectedDetent
        self.onFlightSelected = onFlightSelected
        self.onTabSelected = onTabSelected
        self.onGlobeReset = onGlobeReset
    }
    
    var body: some View {
        // ONE SURFACE, NO TAB SHELL. The bar that used to be built here — a
        // native `TabView` + `Tab`, which genuinely is the iOS 26 system bar —
        // is now `SkyLineFloatingTabBar`, and `ContentView` places it.
        //
        // The rounded rectangle it looked nested inside was never this TabView's
        // doing; it was the sheet's own platter at the old 80pt detent. See
        // `SkyLineFloatingTabBar` for the measurements. Rebuilding the bar by
        // hand is what buys the app a capsule it fully controls — its own glass,
        // its own morph, its own labels in the app's face — and hosting it
        // outside the sheet is what lets it sit on the globe at all.
        //
        // `.tabBarMinimizeBehavior(.onScrollDown)` went with the TabView: there
        // is no UITabBar left to minimise, and the floating bar is always up.
        activePage
            // No bottom padding for the bar here. `ContentView` hangs it off
            // this sheet with `.safeAreaInset(edge: .bottom)`, which already
            // shortens the page's safe area by exactly the bar's height — a
            // number nothing in this file has to know or keep in step with
            // Dynamic Type.
            //
            // NO `.interactiveDismissDisabled()`, and its removal is the other
            // half of dropping the 80pt resting detent. Dragging this sheet down
            // IS how the user gets back to the globe now, and disabling that
            // would strand them on a page with no way out — the bar can open a
            // surface but it cannot close one.
            .presentationDragIndicator(.automatic)
            .sheet(isPresented: $addTripView) {
                AddTripView()
                    .environmentObject(themeManager)
                    .environmentObject(tripStore)
            }
    }

    // MARK: - Active Page

    /// The one surface this sheet is showing.
    ///
    /// `activeTab` is a `@Binding` now. `ContentView` owns it because the bar
    /// and this page both read it, and one value is the only way a lit slot and
    /// the page under it can never disagree.
    ///
    /// Places gets its own branch and is NOT routed through `IndividualTabView`.
    /// It owns a `NavigationStack`, so it must not be erased — erasure destroys
    /// structural identity and makes SwiftUI rebuild the stack, which is how
    /// "top item belongs to a different navigation bar" gets raised. Everything
    /// else goes through the one erased branch; see `IndividualTabView` for why
    /// that erasure is load-bearing.
    ///
    /// `.id(activeTab)` gives each surface its own identity. Both legacy pages
    /// resolve to the same `AnyView` type, so without it SwiftUI would reuse one
    /// ScrollView between them and Profile would open at whatever offset Flights
    /// was left scrolled to. It keys on the TAB, not the detent, so opening and
    /// closing the sheet still does not scroll a list back to the top.
    @ViewBuilder
    private var activePage: some View {
        if activeTab == .places {
            PlacesTabPage()
        } else {
            pageSlab { IndividualTabView(activeTab) }
                .id(activeTab)
        }
    }
    
    /// The Places page, and the ONLY page not built by `IndividualTabView`.
    ///
    /// Splitting it out is not cosmetic. With the page style gone (see the
    /// TabView above) the four tabs no longer need to share one type, and while
    /// they DID share one - `_ConditionalContent<placesSubtree, AnyView>`, the
    /// Places subtree inlined into the same type as the three legacy surfaces -
    /// type-checking `body` did not terminate: xcodebuild sat in SwiftCompile on
    /// this file for over ten minutes. Giving Places its own concrete type
    /// leaves `IndividualTabView` returning a flat `AnyView` and the file
    /// compiles in the usual couple of minutes.
    ///
    /// It also keeps `PlaceLogView` out of the erased branch, which matters for
    /// a different reason: this view owns a `NavigationStack`, and erasing a
    /// view that owns navigation destroys its structural identity and makes
    /// SwiftUI rebuild the stack underneath it. Erase types that are DEEP, never
    /// views that own navigation.
    @ViewBuilder
    private func PlacesTabPage() -> some View {
        // PlaceLogView owns its own NavigationStack, large title, search field
        // and scroll view. Wrapping it in the shared ScrollView + header that the
        // other tabs use would give it two titles and two scroll views, so it is
        // hosted bare.
        PlaceLogView(onAddTrip: { addTripView = true })
            .environmentObject(themeManager)
            .background(.clear)
            // No `.toolbarVisibility(.hidden, for: .tabBar)` and no
            // `.toolbarBackgroundVisibility(.hidden, ...)`. There is no system
            // tab bar in this sheet to hide any more, and the floating bar
            // `ContentView` hangs off the sheet is not a toolbar, so neither
            // modifier has anything to act on.
    }

    /// The page's own ground.
    ///
    /// It fills the whole sheet, the strip the floating bar sits in included, so
    /// a page reads as one surface with the bar hovering on it — and so the
    /// bar's glass has the app's own colour to sample rather than a system fill.
    @ViewBuilder
    private func pageSlab<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: AppRadius.sheet,
                    bottomTrailingRadius: AppRadius.sheet,
                    style: .continuous
                )
                .fill(themeManager.currentTheme.colors.background)
                // Runs UNDER the bar, deliberately. `ContentView` hangs the bar
                // off this sheet with `.safeAreaInset(edge: .bottom)`, so the
                // bar lives in the bottom safe area and the page's own ground
                // has to reach through it. Stopping at the safe area instead
                // leaves that strip showing the sheet's system-grey platter
                // rather than the app's `background`, which reads as a two-tone
                // band across the bottom of every page.
                //
                // Only safe because the bar is ABOVE this now. While the bar was
                // behind the sheet, this same line drew the page over it.
                .ignoresSafeArea(.all, edges: .bottom)
            }
    }

    /// Individual Tab View - Trips, Flights and Profile.
    ///
    /// Returns `AnyView`, deliberately, and this is load-bearing rather than
    /// laziness.
    ///
    /// Every surface in this file is a @ViewBuilder FUNCTION, and a function is
    /// not a nominal type boundary the way a `struct: View` is - its whole view
    /// tree is inlined into whatever calls it. The tabs, each expanding through
    /// LegacyTabScroll into TripsTabContent / FlightsTabContent /
    /// ModernFlightDetailContent / boardingPassCard and the eight builders under
    /// that, all landed in ONE concrete type for `body`. Instantiating that
    /// type's metadata at launch recursed through `decodeMangledType` until it
    /// hit the stack guard page: EXC_BAD_ACCESS / SIGSEGV on a real device,
    /// every launch, before a frame was drawn.
    ///
    /// Erasing here cuts those subtrees out of `body`'s type and lets each be
    /// instantiated separately and shallowly. The real fix is to make these
    /// surfaces their own `View` structs; until then, do not remove the erasure.
    /// None of these three owns a navigation stack, so one shared erased type is
    /// safe for them in a way it is not for Places.
    func IndividualTabView(_ tab: SkyLineTab) -> some View {
        AnyView(LegacyTabScroll(tab))
    }

    /// True when the flights surface is showing one flight rather than the list.
    private var isShowingFlightDetail: Bool {
        selectedFlightForDetails != nil
            && (selectedDetent == .fraction(0.3) || selectedDetent == .fraction(0.6) || selectedDetent == .large)
    }

    /// The Trips / Flights / Profile surfaces, which still share one scroll view
    /// and one hand-rolled header.
    @ViewBuilder
    private func LegacyTabScroll(_ tab: SkyLineTab) -> some View {
        // The flight detail is hosted OUTSIDE this scroll view, not inside it.
        //
        // `ModernFlightDetailContent` builds its own `ScrollView`, so putting it
        // in here nested one inside another - and because the outer one is the
        // same instance the list was using, it kept the list's offset. Tapping a
        // flight near the bottom of a long list opened its boarding pass already
        // scrolled to the bottom, looking at "Add to Trip". Recreating the
        // CONTENT with `flightDetailsViewKey` could never fix that: the scroll
        // position belongs to the scroll view, and that was the one thing being
        // preserved.
        if tab == .flights, let selectedFlight = selectedFlightForDetails, isShowingFlightDetail {
            ModernFlightDetailContent(flight: selectedFlight, theme: themeManager)
                .id(flightDetailsViewKey)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(.clear)
        } else {
            legacyTabList(tab)
        }
    }

    private func legacyTabList(_ tab: SkyLineTab) -> some View {
        ScrollView(.vertical) {
            // One explicit stack rather than two siblings in the ScrollView's
            // implicit one, so the gap between header and content is on the grid
            // instead of being SwiftUI's default.
            VStack(spacing: 0) {
                TabHeader(tab)

                // Tab-specific content
                switch tab {
                case .places:
                    // Unreachable: `.places` is routed to PlaceLogView above.
                    EmptyView()
                case .trips:
                    AnyView(TripsTabContent())
                case .flights:
                    AnyView(FlightsTabContent())
                case .profile:
                    AnyView(ProfileTabContent())
                }
            }
            // The system bar floats over the end of this content. SwiftUI adds
            // its own bottom inset for the bar; this is the breathing room on
            // top of it, so the last row does not sit against the glass.
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(.clear)
        // Softens the fade where content passes under the glass bar. `.soft`
        // rather than `.hard`: a hairline over the globe reads as a seam.
        .skylineScrollEdges()
        // Nothing fades this page any more. It used to be held at opacity 0 at
        // the 80pt resting detent, where the sheet was 80pt of nothing and a
        // large title would have been drawn across the bar. There is no such
        // detent now: an idle app has no sheet at all, so every height this page
        // can be at is one it should be visible at.
    }

    // MARK: - Tab Header

    /// The large-title row for the legacy surfaces. Its trailing controls sit in a
    /// single `GlassEffectContainer` so adjacent glass circles sample one backdrop
    /// and merge instead of stacking blurs.
    private func TabHeader(_ tab: SkyLineTab) -> some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Flights used to be a sub-surface of Trips and needed a way back.
            // Scoped to boarding-pass scanning, Flights IS the surface and Trips
            // has no slot to go back to, so the chevron is gated on the same
            // `barTabs` array — it returns the moment Trips does.
            if tab == .flights && SkyLineTab.barTabs.contains(.trips) {
                Button {
                    returnToTrips()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(AppTypography.mono(.subheadline, weight: .semibold))
                        Text("Trips")
                            .appFont(.bodySmall, lineLimit: .exactly(1))
                    }
                    .foregroundStyle(theme.colors.primary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back to Trips"))
            }

            HStack(alignment: .top, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(tab.rawValue)
                        .appFont(.titleLarge)
                        .foregroundStyle(theme.colors.text)
                        .accessibilityAddTraits(.isHeader)

                    if let subtitle = headerSubtitle(for: tab) {
                        Text(subtitle)
                            .appFont(.placeMeta, lineLimit: .exactly(1))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Spacer(minLength: AppSpacing.sm)

                SkyLineGlassPanel(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        if tab == .trips {
                            // Flights lost their tab slot; this is how you reach them.
                            SkyLineGlassIconButton(
                                systemImage: "airplane",
                                accessibilityLabel: "Flights"
                            ) {
                                openFlights()
                            }

                            SkyLineGlassIconButton(
                                systemImage: "plus",
                                accessibilityLabel: "Add a trip"
                            ) {
                                addTripView.toggle()
                            }
                        } else if tab == .profile {
                            SkyLineGlassIconButton(
                                systemImage: "gearshape.fill",
                                accessibilityLabel: "Settings"
                            ) {
                                showingSettings = true
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, AppSpacing.md)
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.md)
    }

    private func headerSubtitle(for tab: SkyLineTab) -> String? {
        switch tab {
        case .trips:
            let count = tripStore.trips.count
            return "\(count) trip\(count == 1 ? "" : "s") documented"
        case .flights:
            return "How you got there"
        default:
            return nil
        }
    }

    private var chromeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.3)
    }

    /// List reflow, 0.25s, matching `PlaceLogView`. `nil` under Reduce Motion —
    /// the same computed-Animation pattern the Places screens already use.
    private var listAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    /// Trips -> Flights, the only entry point now that the bar has no flights slot.
    private func openFlights() {
        withAnimation(chromeAnimation) {
            flightNavigationContext = .flights
            selectedFlightForDetails = nil
            activeTab = .flights
        }
        // No `onTabChanged` any more: `activeTab` is a binding, so the write
        // above has already relit the bar's slot. This only asks the sheet to
        // open, and it names the tab rather than letting ContentView re-read a
        // value written in the same update.
        onTabSelected?(.flights)
    }

    /// Flights -> Trips, the matching way back out.
    ///
    /// Unreachable while the app is scoped to boarding passes (its only caller,
    /// the header chevron, is gated on `barTabs`). Routed through `.resolved`
    /// anyway so it can never select a page the TabView is not building.
    private func returnToTrips() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        let destination = SkyLineTab.trips.resolved

        onGlobeReset?()
        withAnimation(chromeAnimation) {
            selectedFlightForDetails = nil
            flightNavigationContext = .flights
            activeTab = destination
        }
    }

    // MARK: - Tab Bar (superseded)

    /// IF A `TabView` EVER COMES BACK TO THIS SHEET: NO
    /// `.tabViewStyle(PageTabViewStyle(...))`. Its absence was load-bearing and
    /// the reason is still true, so it is written down here rather than deleted
    /// with the TabView it used to hang off.
    ///
    /// The page style backs a TabView with a UICollectionView
    /// (`SwiftUI.PagingCollectionView`) and hosts each tab in a RECYCLED
    /// `UIKitPagingCell`. The Places tab is `PlaceLogView`, which owns a
    /// `NavigationStack`, and SwiftUI bridges that to a real
    /// `UIKitNavigationController` + `UIKitNavigationBar` living inside that
    /// cell.
    ///
    /// This sheet resizes constantly, and tapping a tab animates the detent at
    /// the same moment as it changes the page. A resize makes the paging layout
    /// momentarily invalid ("the item height must be less than the height of the
    /// UICollectionView"), which resets the collection view's contentOffset and
    /// makes the pager write `activeTab` back to `.places` on its own,
    /// mid-layout. The Places cell is then rebuilt inside that same layout pass,
    /// and because the page's view IDENTITY has not changed SwiftUI reuses the
    /// existing root hosting controller — so a SECOND navigation controller
    /// adopts the SAME `UINavigationItem`. Two live `UIKitNavigationBar`s then
    /// claim one item; the first is still in the window, so the rest of the
    /// sheet resize walks the autoresizing chain into it
    /// (`-[UISheetPresentationController _updatePresentedViewFrame]` ->
    /// `-[UINavigationBar layoutSubviews]`), UIKit finds
    /// `topItem.navigationBar != self` and raises
    /// NSInternalInconsistencyException: "Layout requested for visible
    /// navigation bar ... when the top item belongs to a different navigation
    /// bar". SIGABRT, and the reason is only in the console — never in the .ips.
    ///
    /// The default style is backed by a UITabBarController, whose child view
    /// controllers are created once and RETAINED, so the navigation stack is
    /// hosted exactly once and can never be duplicated. `TabViewHelper` at the
    /// bottom of this file was written for exactly that controller.
    ///
    /// The sheet has no TabView at all today — it builds one page for
    /// `activeTab` — so none of this is live. It is here for whoever puts one
    /// back.
    private enum PageStyleWarning {}


    /// SUPERSEDED BY THE SYSTEM BAR. Nothing calls this; `body` builds `Tab`
    /// items and iOS 26 draws the bar itself. Kept, not deleted, because this
    /// app is scoped and surfaces get switched back — but a call to it would put
    /// a SECOND bar under the real one, which is the failure mode to watch for.
    ///
    /// It was an honest approximation of Liquid Glass and it was still an
    /// approximation: a capsule of `.chrome` glass with a hand-morphed selection
    /// pill, sampling `SkyLineGlobeScrim` instead of the page it belongs to.
    ///
    /// Custom Tab Bar with Liquid Glass Effect
    ///
    /// A floating glass bar rather than an opaque slab bolted to the bottom: it
    /// hovers clear of the safe area with the globe visible around it. That is
    /// also why `ContentView` lays `SkyLineGlobeScrim` under the sheet — glass
    /// needs predictable luminance behind it, and a live 3D globe is not that.
    @ViewBuilder
    func CustomTabBar() -> some View {
        // Corner radius is deliberately not passed: 28 is `SkyLineGlassBar`'s own
        // default and belongs to the component, not to this call site.
        SkyLineGlassBar(
            cornerRadius: 30,
            horizontalPadding: AppSpacing.xs + 2,
            verticalPadding: AppSpacing.xs + 2
        ) {
            // spacing 0: the slots already divide the width evenly, and a gap
            // between them would stop the selection morphing cleanly across.
            HStack(spacing: 0) {
                ForEach(SkyLineTab.barTabs, id: \.rawValue) { tab in
                    TabBarItem(tab)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .id(refreshID)
        .onReceive(themeManager.$currentTheme) { _ in
            refreshID = UUID()
        }
    }

    /// SUPERSEDED, with `CustomTabBar` above. The bar that ships is
    /// `SkyLineFloatingTabBar`, at the bottom of this file, hosted by
    /// `ContentView` so its glass has the globe behind it. What lived here that
    /// still matters moved there: the `barRepresentative` lookup for which slot
    /// lights, and the glass selection capsule.
    ///
    /// One slot in the bar. Flights has no slot of its own, so while it is showing
    /// the Trips slot stays lit — that is what `barRepresentative` encodes.
    @ViewBuilder
    private func TabBarItem(_ tab: SkyLineTab) -> some View {
        let theme = themeManager.currentTheme
        let isActive = activeTab.barRepresentative == tab

        Button {
            print("🎯 Tab tapped: \(tab.rawValue)")
            withAnimation(chromeAnimation) {
                activeTab = tab
            }

            // Trigger sheet expansion when tab is tapped. The globe needs no
            // separate message: `activeTab` is a binding to ContentView, which
            // is what feeds `WebViewGlobeView(currentTab:)`.
            onTabSelected?(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbolImage)
                    .font(AppTypography.mono(.title2, weight: .semibold))
                    .symbolVariant(isActive ? .fill : .none)
                    .symbolRenderingMode(.hierarchical)

                Text(tab.rawValue)
                    .font(AppTypography.mono(.caption2, weight: .medium))
                    .tracking(0.4)
            }
            .foregroundStyle(isActive ? theme.colors.primary : theme.colors.textSecondary)
            // The pill hugs its label instead of spanning the slot. With two
            // tabs `maxWidth: .infinity` made the selection half the bar wide -
            // a slab, not an indicator - and the unselected item looked like a
            // hole next to it. The tap target below is still the full slot.
            .padding(.horizontal, AppSpacing.md + 2)
            .padding(.vertical, AppSpacing.sm)
            .background {
                if isActive {
                    // Real glass, not a painted tint. The old
                    // `Capsule().fill(primary.opacity(0.12))` is what made this
                    // read as a flat grey-blue slab sitting on the bar: an
                    // opaque fill samples nothing, so it cannot pick up the
                    // globe behind it the way the bar around it does.
                    //
                    // `glassEffectID` in a shared namespace is what makes the
                    // selection MORPH from one slot to the next rather than
                    // cross-fading - the behaviour that reads as Liquid Glass.
                    Color.clear
                        .skylineGlass(
                            .control,
                            in: Capsule(style: .continuous),
                            tint: theme.colors.primary,
                            interactive: true,
                            theme: theme
                        )
                        .glassEffectID("SkyLineTabSelection", in: tabSelectionNamespace)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.rawValue))
        // VoiceOver has no other way to tell which slot is lit — the tint and the
        // capsule are visual only.
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Flight Selection Handler
    
    private func handleFlightSelectedFromTrip(_ flight: Flight, _ trip: Trip) {
        // Set navigation context to remember we came from a trip
        flightNavigationContext = .trip(trip)
        
        // Switch to flights tab
        activeTab = .flights
        
        // Select the flight for details view
        selectedFlightForDetails = flight
        selectedFlightId = flight.id
        
        // Update the detent to show flight details
        selectedDetent = .fraction(0.6)
        
        // Refresh the view to ensure proper display
        flightDetailsViewKey = UUID()
        
        // Call the parent callback if needed. `activeTab` above is a binding,
        // so ContentView and the bar already know which surface this is.
        onFlightSelected?(flight)
    }
    
    // MARK: - Tab Content Views
    
    @ViewBuilder
    func TripsTabContent() -> some View {
        TripsListView(onFlightSelected: handleFlightSelectedFromTrip, externalTripSelection: tripToReopen)
            .environmentObject(tripStore)
    }
    
    @ViewBuilder
    func FlightsTabContent() -> some View {
        // No inner ScrollView: `LegacyTabScroll` already owns one, and nesting an
        // unbounded vertical scroll view inside it collapses this content's height.
        VStack(spacing: AppSpacing.md) {
            if !flightStore.flights.isEmpty {
                FlightFilterSegmentedControl(selectedFilter: $selectedFlightFilter)
                    .environmentObject(themeManager)
                    .padding(.horizontal, AppSpacing.md)
            }

            if flightStore.flights.isEmpty {
                FlightsEmptyStateView(kind: .noFlights)
                    .environmentObject(themeManager)
            } else {
                let filteredFlights = filteredFlightsList

                if filteredFlights.isEmpty {
                    FlightsEmptyStateView(
                        kind: selectedFlightFilter == .upcoming ? .noUpcoming : .noPast
                    )
                    .environmentObject(themeManager)
                } else {
                    LazyVStack(spacing: AppSpacing.md) {
                        ForEach(filteredFlights) { flight in
                            FlightRowView(
                                flight: flight,
                                isSelected: selectedFlightId == flight.id,
                                onTap: {
                                    handleFlightTap(flight)
                                },
                                onDelete: {
                                    handleFlightDelete(flight)
                                }
                            )
                            .id("\(flight.id)-\(refreshID)")
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .animation(listAnimation, value: selectedFlightFilter)
                }
            }
        }
    }

    private var filteredFlightsList: [Flight] {
        let now = Date()
        switch selectedFlightFilter {
        case .upcoming:
            return flightStore.sortedFlights.filter { ($0.departureDate ?? $0.date) >= now }
        case .past:
            return flightStore.sortedFlights.filter { ($0.departureDate ?? $0.date) < now }
        }
    }
    
    
    @ViewBuilder
    func ProfileTabContent() -> some View {
        let theme = themeManager.currentTheme

        // No inner ScrollView: this is already inside `LegacyTabScroll`'s scroll
        // view, and a nested unbounded one fights it for the drag.
        VStack(spacing: AppSpacing.lg) {
            profileIdentity(theme: theme)
            profileStats(theme: theme)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.xs)
        .frame(maxWidth: .infinity)
        .task {
            // Fetch profile image from CloudKit
            await loadProfileImage()
        }
        .onChange(of: showingEditProfile) { _, isShowing in
            if !isShowing {
                // Refresh profile image when edit sheet is dismissed
                Task {
                    await loadProfileImage()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(themeManager)
                .environmentObject(authService)
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(themeManager)
                .environmentObject(authService)
        }
    }

    @ViewBuilder
    private func profileIdentity(theme: AppTheme) -> some View {
        Button {
            showingEditProfile = true
        } label: {
            VStack(spacing: AppSpacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let profileImage = profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: avatarSize, height: avatarSize)
                                .clipShape(Circle())
                        } else {
                            // Initials in `primary` on tinted glass, not white on
                            // a `primary` fill: white over dark `primary`
                            // (0x4DA3FF) is 2.6:1 and fails AA. `primary` on the
                            // glass fallback clears AA in both palettes.
                            Text(authService.authenticationState.user?.initials ?? "SU")
                                .appFont(.title, lineLimit: .exactly(1))
                                .foregroundStyle(theme.colors.primary)
                                .frame(width: avatarSize, height: avatarSize)
                                .skylineGlass(
                                    .card,
                                    in: Circle(),
                                    tint: theme.colors.primary.opacity(0.22),
                                    theme: theme
                                )
                        }
                    }

                    Image(systemName: "pencil")
                        .font(AppTypography.mono(.caption, weight: .semibold))
                        .foregroundStyle(theme.colors.text)
                        .frame(width: avatarBadge, height: avatarBadge)
                        .skylineGlass(.control, in: Circle(), theme: theme)
                        .offset(x: AppSpacing.xs, y: -AppSpacing.xs)
                }

                VStack(spacing: AppSpacing.xs) {
                    Text(authService.authenticationState.user?.displayName ?? "SkyLine User")
                        .appFont(.headline)
                        .foregroundStyle(theme.colors.text)

                    if let email = authService.authenticationState.user?.email {
                        Text(email)
                            .appFont(.placeMeta, lineLimit: .exactly(1))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Edit profile"))
    }

    @ViewBuilder
    private func profileStats(theme: AppTheme) -> some View {
        let tripCount = tripStore.trips.count
        let countryCount = calculateCountriesVisited()
        let flightCount = flightStore.flights.count

        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            HStack(spacing: 0) {
                statColumn(value: tripCount, label: tripCount == 1 ? "trip" : "trips")
                statDivider
                statColumn(value: countryCount, label: countryCount == 1 ? "country" : "countries")
                statDivider
                statColumn(value: flightCount, label: flightCount == 1 ? "flight" : "flights")
            }
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.sm)
            .frame(maxWidth: .infinity)
            // Glass, not `surface` + shadow. A black shadow on 0x0A0F1C has
            // nowhere to go, so on dark the old card had no edge at all.
            .skylineGlassCard(theme: theme)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(tripCount) trips in \(countryCount) countries, \(flightCount) flights.")
        )
    }

    // MARK: - Profile Tab Helper Functions

    /// One column of the profile stat row, matching `PlaceLogView.statColumn`
    /// exactly so the two screens read as one system. The icons are gone: value
    /// plus label is two type tokens, and adding a glyph made three graphic
    /// layers competing inside a 100pt-wide column.
    @ViewBuilder
    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text("\(value)")
                .appFont(.title, lineLimit: .exactly(1))
                .foregroundStyle(themeManager.currentTheme.colors.text)
                .contentTransition(.numericText())

            Text(label.uppercased())
                .appFont(.footnote, lineLimit: .exactly(1))
                .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// A ruled line from the palette. A bare `Divider()` is a semantic separator
    /// and follows the DEVICE appearance, not the theme the user picked.
    private var statDivider: some View {
        Rectangle()
            .fill(themeManager.currentTheme.colors.border)
            .frame(width: 1, height: 28)
            .accessibilityHidden(true)
    }

    // MARK: - Statistics Calculations

    private func calculateCountriesVisited() -> Int {
        let countries = Set(tripStore.trips.compactMap { $0.country })
        return countries.count
    }

    private func loadProfileImage() async {
        guard let user = authService.authenticationState.user else { return }

        do {
            if let image = try await CloudKitService.shared.fetchUserProfileImage(userId: user.id) {
                await MainActor.run {
                    profileImage = image
                }
            } else {
                await MainActor.run {
                    profileImage = nil
                }
            }
        } catch {
            print("❌ Failed to load profile image: \(error)")
            await MainActor.run {
                profileImage = nil
            }
        }
    }

    // MARK: - Modern Flight Detail Content Component
    
    /// The flight detail surface.
    ///
    /// The ticket metaphor survives — it is the app's one piece of skeuomorphism
    /// and it earns its place — but it was hard-designed for dark: literal black
    /// fills, white hairlines, a black-backed CTA. Every layer now comes from the
    /// palette, so the perforation notches read as the page showing through in
    /// both themes rather than as black holes punched in a white card.
    func ModernFlightDetailContent(flight: Flight, theme: ThemeManager) -> some View {
        let appTheme = theme.currentTheme
        let colors = appTheme.colors

        return ScrollView {
            VStack(spacing: AppSpacing.lg) {
                flightDetailHeader(flight: flight, colors: colors)
                AnyView(boardingPassCard(flight: flight, appTheme: appTheme))
                flightDetailActions(colors: colors)
            }
            .padding(.top, AppSpacing.md)
            // Clearance for the tab bar, which floats over the globe below the slab.
            .padding(.bottom, AppSpacing.xxl)
        }
        .sheet(isPresented: $showingAddToTripSheet) {
            if let flight = selectedFlightForDetails {
                AddFlightToTripView(flight: flight)
                    .environmentObject(themeManager)
                    .environmentObject(TripStore.shared)
            } else {
                AddFlightToTripView(flight: flightStore.selectedFlight ?? Flight.sample)
                    .environmentObject(themeManager)
                    .environmentObject(TripStore.shared)
            }
        }
    }

    @ViewBuilder
    private func flightDetailHeader(flight: Flight, colors: ThemeColors) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(flight.flightNumber)
                    .appFont(.title)
                    .foregroundStyle(colors.text)
                    .accessibilityAddTraits(.isHeader)

                Text("\(flight.departure.code) \u{2192} \(flight.arrival.code)")
                    .appFont(.placeMeta, lineLimit: .exactly(1))
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer(minLength: AppSpacing.sm)

            // Glass, because this control can end up over the globe when the
            // sheet is short. An opaque circle would be the only non-glass
            // control on the surface.
            SkyLineGlassIconButton(
                systemImage: "xmark",
                accessibilityLabel: "Close flight details"
            ) {
                closeFlightDetails()
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    /// Extracted verbatim from the old close button so the navigation-context
    /// branch, the globe reset and the detent changes all behave identically.
    private func closeFlightDetails() {
        print("\u{1F50D} DEBUG: Close button tapped")

        onGlobeReset?()
        withAnimation(chromeAnimation) {
            // The card highlight is a different piece of state from the detail
            // screen, and only the screen was being cleared - so a flight you
            // opened and closed stayed lit for the rest of the session.
            selectedFlightId = nil

            switch flightNavigationContext {
            case .flights:
                selectedFlightForDetails = nil
                // 0.3, not 0.2: the floating bar hangs off this sheet as a
                // bottom safe-area inset and costs ~110pt at every height, so
                // 0.2 is no longer a detent the sheet has.
                selectedDetent = .fraction(0.3)
            case .trip(let trip):
                selectedFlightForDetails = nil
                // `.resolved` because Trips is hidden while the app is scoped to
                // boarding passes; this lands back on Flights instead of on a
                // page the TabView is not building.
                activeTab = SkyLineTab.trips.resolved
                selectedDetent = .fraction(0.3)

                tripToReopen = trip

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    tripToReopen = nil
                }

                flightNavigationContext = .flights
            }
            flightDetailsViewKey = UUID()
            print("\u{1F50D} DEBUG: Context-aware navigation completed")
        }
    }

    @ViewBuilder
    private func flightDetailActions(colors: ThemeColors) -> some View {
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    showingAddToTripSheet = true
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "folder.badge.plus")
                            .font(AppTypography.mono(.body, weight: .semibold))
                        Text("Add to Trip")
                            .appFont(.bodyBold, lineLimit: .exactly(1))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                }
                // The one loud use of `primary` on this screen.
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(colors.primary)

                SkyLineGlassIconButton(
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: "Share flight"
                ) {
                    // TODO: Share flight
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    // MARK: - Boarding Pass Card

    @ViewBuilder
    private func boardingPassCard(flight: Flight, appTheme: AppTheme) -> some View {
        let colors = appTheme.colors

        VStack(spacing: 0) {
            passIdentity(flight: flight, colors: colors)
            passRoute(flight: flight, colors: colors)
            passDetailWell(flight: flight, colors: colors)
            passPerforation(colors: colors)
            passBarcode(flight: flight, colors: colors)
        }
        .padding(.vertical, AppSpacing.md)
        .background(alignment: .topTrailing) {
            Image(systemName: "airplane")
                .font(.system(size: passWatermarkSize, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(colors.text.opacity(0.06))
                .rotationEffect(.degrees(320))
                .offset(x: AppSpacing.lg, y: AppSpacing.md)
                .accessibilityHidden(true)
        }
        // Clip before the glass so the watermark and the notches are bitten off
        // by the card edge instead of bleeding across the page.
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .skylineGlassCard(cornerRadius: AppRadius.card, theme: appTheme)
        .padding(.horizontal, AppSpacing.md)
    }

    @ViewBuilder
    private func passIdentity(flight: Flight, colors: ThemeColors) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "airplane")
                    .font(AppTypography.mono(.body, weight: .semibold))
                    .foregroundStyle(colors.primary)
                    .frame(width: passGlyphWell, height: passGlyphWell)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .fill(colors.primary.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("AIRLINE")
                        .appFont(.footnote, lineLimit: .exactly(1))
                        .foregroundStyle(colors.textSecondary)

                    Text(flight.airline ?? "Unknown")
                        .appFont(.bodyBold, lineLimit: .exactly(1))
                        .foregroundStyle(colors.text)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text("FLIGHT")
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(colors.textSecondary)

                Text(flight.flightNumber)
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(colors.text)
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    @ViewBuilder
    private func passRoute(flight: Flight, colors: ThemeColors) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            passEndpoint(
                code: flight.departure.code,
                city: flight.departure.city,
                time: flight.departure.displayTime,
                date: formatDate(flight.departureDate ?? flight.date),
                isDeparture: true,
                colors: colors
            )

            VStack(spacing: AppSpacing.sm) {
                routeLine(colors: colors)

                Text(flight.flightDuration ?? calculateFlightDuration(flight: flight))
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(colors.primary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background {
                        Capsule(style: .continuous)
                            .fill(colors.primary.opacity(0.12))
                    }
            }
            // Half the 34pt code, so the line runs through the codes rather than
            // above them.
            .padding(.top, AppSpacing.md)

            passEndpoint(
                code: flight.arrival.code,
                city: flight.arrival.city,
                time: flight.arrival.displayTime,
                date: formatDate(flight.arrivalDate ?? flight.date),
                isDeparture: false,
                colors: colors
            )
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.lg)
    }

    @ViewBuilder
    private func passEndpoint(code: String, city: String, time: String, date: String, isDeparture: Bool, colors: ThemeColors) -> some View {
        VStack(alignment: isDeparture ? .leading : .trailing, spacing: AppSpacing.xs) {
            // `titleLarge` rather than a frozen 53pt: monospaced advance width is
            // ~0.6em, so three characters at 53pt plus a city underneath is what
            // pushed this row off a 375pt screen.
            Text(code)
                .appFont(.titleLarge, lineLimit: .exactly(1))
                .foregroundStyle(colors.text)

            Text(city.uppercased())
                .appFont(.footnote, lineLimit: .exactly(1))
                .foregroundStyle(colors.textSecondary)

            VStack(alignment: isDeparture ? .leading : .trailing, spacing: AppSpacing.xs) {
                Text(time)
                    .appFont(.flightTime, lineLimit: .exactly(1))
                    .foregroundStyle(colors.primary)

                Text(date.uppercased())
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.top, AppSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: isDeparture ? .leading : .trailing)
    }

    @ViewBuilder
    private func passDetailWell(flight: Flight, colors: ThemeColors) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "person")
                    .font(AppTypography.mono(.body, weight: .semibold))
                    .foregroundStyle(colors.primary)
                    .frame(width: passGlyphWell, height: passGlyphWell)
                    .background {
                        Circle().fill(colors.primary.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("PASSENGER")
                        .appFont(.footnote, lineLimit: .exactly(1))
                        .foregroundStyle(colors.textSecondary)

                    // Was a hardcoded name. The signed-in user is the passenger.
                    Text(authService.authenticationState.user?.displayName ?? "Passenger")
                        .appFont(.bodyBold, lineLimit: .exactly(1))
                        .foregroundStyle(colors.text)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text("STATUS")
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(colors.textSecondary)

                HStack(spacing: AppSpacing.xs) {
                    statusDot(for: flight.status)
                    Text(flight.status.displayName)
                        .appFont(.bodyBold, lineLimit: .exactly(1))
                        .foregroundStyle(colors.text)
                }
            }
        }
        .padding(AppSpacing.md)
        .background {
            ConcentricRectangle(corners: .concentric, isUniform: true)
                .fill(colors.surface)
        }
        .overlay {
            ConcentricRectangle(corners: .concentric, isUniform: true)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.lg)
    }

    @ViewBuilder
    private func passPerforation(colors: ThemeColors) -> some View {
        ZStack {
            PassPerforationLine()
                .stroke(colors.border, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .frame(height: 1)
                .padding(.horizontal, AppSpacing.xl)

            HStack(spacing: 0) {
                passNotch(colors: colors)
                    .offset(x: -passNotchSize / 2)
                Spacer(minLength: 0)
                passNotch(colors: colors)
                    .offset(x: passNotchSize / 2)
            }
        }
        .frame(height: passNotchSize)
        .padding(.top, AppSpacing.lg)
        .accessibilityHidden(true)
    }

    /// The bite out of the ticket edge. Filled with `background` because that is
    /// literally what is behind the card — which is why the old `Color.black`
    /// looked right on dark and like a hole punched in paper on light.
    @ViewBuilder
    private func passNotch(colors: ThemeColors) -> some View {
        Circle()
            .fill(colors.background)
            .frame(width: passNotchSize, height: passNotchSize)
            .overlay {
                Circle().stroke(colors.border, lineWidth: 1)
            }
    }

    @ViewBuilder
    private func passBarcode(flight: Flight, colors: ThemeColors) -> some View {
        // Deterministic, seeded from the flight number. The old version called
        // `Double.random` inside `body`, so every re-render reshuffled the bars.
        let seed = flight.flightNumber.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }

        VStack(spacing: AppSpacing.md) {
            HStack(spacing: 2) {
                ForEach(0..<56, id: \.self) { i in
                    let widths: [CGFloat] = [1, 2, 3, 1, 4, 2, 1, 3]
                    let step = (i &+ seed) % widths.count
                    Capsule(style: .continuous)
                        .fill(colors.text.opacity(step == 0 ? 0.3 : 0.7))
                        .frame(width: widths[step], height: barcodeHeight)
                }
            }
            .frame(height: barcodeHeight)
            .padding(.horizontal, AppSpacing.lg)

            HStack(alignment: .top, spacing: AppSpacing.sm) {
                passStamp(label: "TERMINAL", value: flight.departure.terminal ?? "\u{2014}", colors: colors, trailing: false)
                Spacer(minLength: AppSpacing.sm)
                passStamp(label: "GATE", value: flight.departure.gate ?? "\u{2014}", colors: colors, trailing: true)
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .padding(.top, AppSpacing.lg)
    }

    @ViewBuilder
    private func passStamp(label: String, value: String, colors: ThemeColors, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: AppSpacing.xs) {
            Text(label)
                .appFont(.footnote, lineLimit: .exactly(1))
                .foregroundStyle(colors.textSecondary)
            Text(value)
                .appFont(.bodyBold, lineLimit: .exactly(1))
                .foregroundStyle(colors.text)
        }
    }

    // MARK: - Shared Flight Primitives

    /// The hairline route with an aeroplane riding it. Shared by the flight rows
    /// and the boarding pass so the two surfaces read as the same family.
    @ViewBuilder
    func routeLine(colors: ThemeColors) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Rectangle()
                .fill(colors.border)
                .frame(height: 1)

            Image(systemName: "airplane")
                .font(AppTypography.mono(.caption, weight: .semibold))
                .foregroundStyle(colors.primary)

            Rectangle()
                .fill(colors.border)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    func statusDot(for status: FlightStatus) -> some View {
        Circle()
            .fill(getStatusColor(for: status))
            .frame(width: statusDotSize, height: statusDotSize)
            .accessibilityHidden(true)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func calculateFlightDuration(flight: Flight) -> String {
        // Use separate departure and arrival dates if available
        let departureDate = flight.departureDate ?? flight.date
        let arrivalDate = flight.arrivalDate ?? flight.date
        
        // Parse departure and arrival times using their respective dates
        let departureTime = parseTimeString(flight.departure.time, date: departureDate)
        let arrivalTime = parseTimeString(flight.arrival.time, date: arrivalDate)
        
        guard let depTime = departureTime, let arrTime = arrivalTime else {
            return "N/A"
        }
        
        // Calculate duration directly (no need for overnight logic since we use actual dates)
        let duration = arrTime.timeIntervalSince(depTime)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        // Handle negative durations (shouldn't happen but just in case)
        if duration < 0 {
            return "N/A"
        }
        
        return String(format: "%dH %02dM", hours, minutes)
    }
    
    private func parseTimeString(_ timeString: String, date: Date) -> Date? {
        let timeFormats = ["HH:mm", "H:mm", "h:mm a", "h:mm"]
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        
        for format in timeFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let timeDate = formatter.date(from: timeString) {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
                
                var combinedComponents = DateComponents()
                combinedComponents.year = dateComponents.year
                combinedComponents.month = dateComponents.month
                combinedComponents.day = dateComponents.day
                combinedComponents.hour = timeComponents.hour
                combinedComponents.minute = timeComponents.minute
                
                return calendar.date(from: combinedComponents)
            }
        }
        
        return nil
    }
    
    @State private var showingAddToTripSheet = false
}

// MARK: - Floating Tab Bar

/// The bar the app ships: a floating Liquid Glass capsule.
///
/// `ContentView` places it, in one of two hosts and never both: in its ZStack
/// over the globe while nothing is open, and as the sheet's bottom
/// `safeAreaInset` while a page is. Same padding either way, so the swap does
/// not move it — measured at (28, 773, 173, 55) for the Flights slot before
/// opening the sheet and again after dismissing it.
///
/// WHAT THE ROUNDED RECTANGLE AROUND THE OLD BAR ACTUALLY WAS. Not a container
/// belonging to the tab bar. It was THE SHEET, at its old 80pt resting detent,
/// which iOS 26 draws as an inset floating platter: 26pt in from each side,
/// 22pt up from the bottom, filled `#1C1C1E`. Measured, not assumed —
///   • the shape occupies y 2343…2557, x 77…1128 at 3x both BEFORE this change
///     and after the tab bar was taken out of the sheet entirely, which is not
///     something a tab bar's own chrome can do;
///   • `#1C1C1E` is `UIColor.systemBackground` dark, and no token in
///     `ThemeColors` is that value;
///   • `.presentationBackground(Color.red)` turns it red, so the modifier does
///     reach the sheet — but `.presentationBackground(Color.red.opacity(0.35))`
///     comes back rgb(107,41,47), which is red over that grey and not red over
///     the globe (rgb(89,0,8)). The platter sits BEHIND the presentation
///     background and cannot be cleared from SwiftUI.
/// So `UITabBarAppearance` was never going to move it, and neither was anything
/// done to the page slab. The fix was to stop presenting the sheet when there is
/// no surface to show; see `skylineGlobeSheetChrome`.
///
/// On the globe the bar has `SkyLineGlobeScrim` and the live globe behind it,
/// which is the backdrop worth refracting; on a page it has the page's own
/// ground. The cost of leaving the system bar behind is
/// `.tabBarMinimizeBehavior(.onScrollDown)`, which went with the UITabBar that
/// implemented it: this bar is always up.
///
/// It is a `struct: View` and not a `@ViewBuilder` function. A function is not a
/// nominal type boundary — its whole tree inlines into the caller's concrete
/// type — and this file has already shipped a launch crash from exactly that.
struct SkyLineFloatingTabBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The surface showing right now. `ContentView` owns it and the sheet's page
    /// reads the same binding, so a lit slot and the page under it cannot
    /// disagree.
    @Binding var activeTab: SkyLineTab

    /// A TAP on a slot, and only a tap. Code that switches surfaces writes
    /// `activeTab` directly, so a programmatic change still leaves the sheet at
    /// whatever height the user put it.
    var onSelect: (SkyLineTab) -> Void

    /// The trailing round action. Adding a flight is the app's one job, so it
    /// gets a permanent affordance rather than living behind a tab: this is
    /// reachable from the globe, with no surface open at all. Optional so a
    /// build without it just renders the tab capsule.
    var onAdd: (() -> Void)? = nil

    /// Shared by every slot's selection capsule. `glassEffectID` means nothing
    /// to glass that is not inside a `GlassEffectContainer` sharing this
    /// namespace, which is why the container below is not optional decoration.
    @Namespace private var glassNamespace

    var body: some View {
        let theme = themeManager.currentTheme

        // `spacing` is the distance within which two pieces of glass in this
        // container stop being two shapes and flow into one. The selection
        // capsule sits INSIDE the bar capsule, so a generous value here
        // dissolves the selection into the bar and the bar looks empty. `xs` is
        // enough for the morph to read and small enough to keep them apart.
        GlassEffectContainer(spacing: AppSpacing.xs) {
            // The action is a SEPARATE piece of glass beside the capsule, not a
            // fourth slot inside it. A slot means "a surface you are on", and
            // this is not somewhere you can be - it is something you do. The
            // gap is `sm`, wider than the container's `xs` merge distance, so
            // the two shapes stay two shapes instead of flowing together.
            HStack(spacing: AppSpacing.sm) {
                tabCapsule(theme: theme)
                    // Measured, not guessed. The capsule's height comes from its
                    // label, its slot padding and its own inset, all of which
                    // move with Dynamic Type - so any constant here is only
                    // correct at one text size, and the circle drifts out of
                    // round with the pill at every other.
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        capsuleHeight = height
                    }

                if let onAdd {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onAdd()
                    } label: {
                        Image(systemName: "plus")
                            .font(AppTypography.mono(.title3, weight: .semibold))
                            .foregroundStyle(theme.colors.primary)
                            .frame(width: capsuleHeight, height: capsuleHeight)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .skylineGlass(.chrome, in: .circle, interactive: true, theme: theme)
                    .accessibilityLabel(Text("Add a flight"))
                }
            }
        }
        // The morph. `glassEffectID` decides that the selection capsule is the
        // same element in a new slot; this is what animates it there.
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: activeTab)
        .accessibilityElement(children: .contain)
    }

    /// The tab capsule's measured height, so the round action matches it exactly.
    /// Seeded with a plausible value for the first layout pass only.
    @State private var capsuleHeight: CGFloat = 52

    private func tabCapsule(theme: AppTheme) -> some View {
        HStack(spacing: 0) {
            ForEach(SkyLineTab.barTabs, id: \.rawValue) { tab in
                SkyLineFloatingTabBarSlot(
                    tab: tab,
                    isActive: activeTab.barRepresentative == tab,
                    theme: theme,
                    horizontalPadding: slotHorizontalPadding,
                    glassNamespace: glassNamespace
                ) {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    onSelect(tab)
                }
            }
        }
        .padding(AppSpacing.xs)
            // This IS `.glassEffect(.regular.interactive(), in: .capsule)` —
            // read `SkyLineGlassSurface` — with the Reduce Transparency
            // fallback attached. Calling `.glassEffect` straight would leave
            // anyone who turns transparency off with a bar that has no
            // substance at all over a live globe.
            .skylineGlass(.chrome, in: .capsule, interactive: true, theme: theme)
    }

    /// How much air each slot puts around its label.
    ///
    /// Two slots can afford `md`, and need it: with `barTabs` at
    /// `[.flights, .profile]` a tighter pill reads as a chip rather than a
    /// selection. Restore `.places` and `.trips` and four slots have to share
    /// 375pt minus the bar's own inset, so at the accessibility text sizes
    /// `.footnote` still permits, `md` on both sides of four labels overflows.
    /// Derived from `barTabs` so restoring the surfaces restores the fit too.
    private var slotHorizontalPadding: CGFloat {
        SkyLineTab.barTabs.count > 2 ? AppSpacing.sm : AppSpacing.md
    }
}

/// One slot in `SkyLineFloatingTabBar`.
///
/// Its own type, not a builder function on the bar, for the same reason the bar
/// is: keeping each subtree out of the parent's concrete type.
private struct SkyLineFloatingTabBarSlot: View {
    let tab: SkyLineTab
    let isActive: Bool
    let theme: AppTheme
    let horizontalPadding: CGFloat
    let glassNamespace: Namespace.ID
    let action: () -> Void

    /// ONE id for every slot's capsule, deliberately, and NOT the tab.
    ///
    /// `glassEffectID` is what tells the container that two pieces of glass in
    /// two states are the same piece of glass. Keyed on the tab, the old slot's
    /// capsule and the new slot's capsule are different elements — one removed,
    /// one inserted — and glass that is removed and inserted cross-fades. Keyed
    /// on a constant it is one element that has moved, so the container
    /// interpolates its geometry and the capsule TRAVELS between slots. That
    /// travel is the thing that reads as Liquid Glass; a cross-fade reads as a
    /// highlight blinking sideways.
    private static let selectionGlassID = "SkyLineTabSelection"

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs / 2) {
                Image(systemName: tab.symbolImage)
                    .font(AppTypography.mono(.title3, weight: .semibold))
                    // Colour is never the only signal. The selected glyph is
                    // FILLED and the unselected one is outlined, so which slot
                    // is live still reads in greyscale and without colour
                    // vision.
                    .symbolVariant(isActive ? .fill : .none)
                    .symbolRenderingMode(.hierarchical)

                Text(tab.rawValue)
                    .appFont(.footnote, lineLimit: .exactly(1))
            }
            .foregroundStyle(isActive ? theme.colors.primary : theme.colors.textSecondary)
            // The pill hugs its label instead of spanning the slot. With two
            // tabs, `maxWidth: .infinity` on the capsule made the selection half
            // the bar wide — a slab, not an indicator — and left the unselected
            // slot looking like a hole beside it. The tap target below is still
            // the whole slot.
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, AppSpacing.sm)
            .background {
                if isActive {
                    // Real glass, not a painted tint: an opaque fill samples
                    // nothing, so it cannot pick up the globe the way the bar
                    // around it does, and that is what made the previous
                    // `Capsule().fill(primary.opacity(0.12))` read as a flat
                    // grey-blue slab.
                    //
                    // UNTINTED, which is a change. `Glass.tint(primary)` under
                    // a label that is also `primary` puts blue ink on a blue
                    // wash; `onAccent` cannot rescue it either, because a tinted
                    // glass is not a filled surface and near-black ink over a
                    // translucent wash on a night globe is worse. Plain glass
                    // lightens whatever is behind it, and `primary` measures
                    // 5.9:1 (light) and 7.3:1 (dark) against the palette's own
                    // ground.
                    Color.clear
                        .skylineGlass(
                            .control,
                            in: Capsule(style: .continuous),
                            interactive: true,
                            theme: theme
                        )
                        .glassEffectID(Self.selectionGlassID, in: glassNamespace)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.rawValue))
        // VoiceOver has no other way to know which slot is lit — the tint, the
        // fill variant and the capsule are all visual.
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Previews
/// Both previews stand the sheet on the app's own `background` rather than a
/// literal black, so what you see in the canvas is what the theme actually paints.
private struct BottomBarPreviewHost: View {
    let theme: AppTheme

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var flightStore = FlightStore()

    var body: some View {
        ZStack {
            themeManager.currentTheme.colors.background
                .ignoresSafeArea()

            SkyLineBottomBarView(activeTab: .constant(.primary), selectedDetent: .constant(.large))
                .environmentObject(themeManager)
                .environmentObject(flightStore)
                .environmentObject(AuthenticationService.shared)
        }
        .onAppear { themeManager.currentTheme = theme }
    }
}

#Preview("Bottom bar - dark") {
    BottomBarPreviewHost(theme: .dark)
}

#Preview("Bottom bar - light") {
    BottomBarPreviewHost(theme: .light)
}

private extension SkyLineBottomBarView {
    // Duration calculation removed - will be added in future update
    
    // MARK: - Flight Action Handlers
    
    private func handleFlightTap(_ flight: Flight) {
        print("🔍 DEBUG: Flight tapped - \(flight.flightNumber)")
        print("🔍 DEBUG: Current selectedDetent before tap: \(selectedDetent)")
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            // Set navigation context to flights (normal flight tab navigation)
            flightNavigationContext = .flights
            
            selectedFlightId = flight.id
            selectedFlightForDetails = flight
            flightDetailsViewKey = UUID() // Force view recreation with new key
            print("🔍 DEBUG: Set selectedFlightForDetails to \(flight.flightNumber)")
            print("🔍 DEBUG: Generated new flightDetailsViewKey: \(flightDetailsViewKey)")
            
            // Already at the shortest detent the sheet has, so there is
            // nothing to collapse to. This used to promote 0.2 -> 0.3; 0.2 left
            // with the floating bar's safe-area inset, and 0.3 IS the peek now.
            if selectedDetent == .fraction(0.3) {
                print("🔍 DEBUG: selectedDetent already at the 0.3 peek")
            } else {
                print("🔍 DEBUG: keeping selectedDetent as \(selectedDetent)")
            }
        }
        
        // Call the callback to communicate with ContentView
        onFlightSelected?(flight)
        print("🔍 DEBUG: Called onFlightSelected callback")
    }
    
    private func handleFlightDelete(_ flight: Flight) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Use removeFlightSync to also delete from CloudKit
        Task {
            await flightStore.removeFlightSync(flight.id)
        }
    }
    
    /// One flight in the list.
    ///
    /// Was four elevation signals stacked on one card — fill, corner radius,
    /// stroke and shadow — plus a `scaleEffect` on selection that resampled the
    /// glyphs and made the text soft. Now it is a single glass card whose tint
    /// carries selection, with one recessed well inside it for the secondary
    /// fields. Glass is what actually produces a card in both palettes: `surface`
    /// on `background` is a ~2% luminance step either way, and a black shadow has
    /// nowhere to go on 0x0A0F1C.
    @ViewBuilder
    func FlightRowView(flight: Flight, isSelected: Bool = false, onTap: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        let theme = themeManager.currentTheme
        let colors = theme.colors

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                rowMetaLine(flight: flight, colors: colors)
                rowRoute(flight: flight, colors: colors)
                rowDetailWell(flight: flight, colors: colors)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Selection is a border, not a fill.
        //
        // `tint: primary` washes the entire card in the accent while every
        // label keeps the colour it had - so the route, the times and the
        // airline all became blue ink on a blue ground and the selected card
        // was the one you could not read. A ring marks the same card and
        // touches no contrast: `onAccent` exists for text ON a filled accent
        // surface, and there is no reason to put a whole card there.
        .skylineGlassCard(theme: theme)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(colors.primary, lineWidth: 2)
            }
        }
        .accessibilityLabel(
            Text("\(flight.flightNumber), \(flight.departure.code) to \(flight.arrival.code), \(flight.status.displayName)")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Focus on Globe", systemImage: "globe")
            }

            Button {
                let flightInfo = "\(flight.flightNumber): \(flight.departure.code) \u{2192} \(flight.arrival.code)"
                UIPasteboard.general.string = flightInfo

                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            } label: {
                Label("Copy Info", systemImage: "doc.on.doc")
            }

            // A menu separator, not a page divider — this is the one place
            // `Divider()` still means what it says.
            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Flight", systemImage: "trash")
            }
        } preview: {
            rowContextPreview(flight: flight, colors: colors)
        }
    }

    @ViewBuilder
    private func rowMetaLine(flight: Flight, colors: ThemeColors) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text(DateFormatter.flightCardDate.string(from: flight.date))
                .appFont(.placeMeta, lineLimit: .exactly(1))
                .foregroundStyle(colors.textSecondary)

            Spacer(minLength: AppSpacing.xs)

            // Status is metadata, not identity: a dot carries the hue and the
            // label carries the meaning. The old filled pill put white glyphs on
            // `statusInAir` (0x3DDC91 on dark) at roughly 1.9:1.
            statusDot(for: flight.status)

            Text(flight.status.displayName.uppercased())
                .appFont(.flightStatus, lineLimit: .exactly(1))
                .foregroundStyle(colors.textSecondary)
        }
    }

    @ViewBuilder
    private func rowRoute(flight: Flight, colors: ThemeColors) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            rowEndpoint(
                code: flight.departure.code,
                city: flight.departure.city,
                time: flight.departure.displayTime,
                isDeparture: true,
                colors: colors
            )

            // Optically centred against the 28pt code, not the top of the column:
            // time (15) + gap (4) + half the code.
            routeLine(colors: colors)
                .padding(.top, AppSpacing.xl)

            rowEndpoint(
                code: flight.arrival.code,
                city: flight.arrival.city,
                time: flight.arrival.displayTime,
                isDeparture: false,
                colors: colors
            )
        }
    }

    @ViewBuilder
    private func rowEndpoint(code: String, city: String, time: String, isDeparture: Bool, colors: ThemeColors) -> some View {
        VStack(alignment: isDeparture ? .leading : .trailing, spacing: AppSpacing.xs) {
            Text(time)
                .appFont(.flightTime, lineLimit: .exactly(1))
                .foregroundStyle(colors.textSecondary)

            Text(code)
                .appFont(.title, lineLimit: .exactly(1))
                .foregroundStyle(colors.text)

            Text(city)
                .appFont(.placeMeta, lineLimit: .exactly(1))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: isDeparture ? .leading : .trailing)
    }

    @ViewBuilder
    private func rowDetailWell(flight: Flight, colors: ThemeColors) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("AIRLINE")
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(colors.textSecondary)

                Text(flight.airline ?? "Unknown")
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(colors.text)
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text("FLIGHT")
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(colors.textSecondary)

                Text(flight.flightNumber)
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(colors.text)
            }
        }
        .padding(AppSpacing.md)
        // Recessed, not lifted: opaque `surface` with a hairline is the inverse
        // of the glass card around it, which is exactly what `systemGray6` was
        // reaching for before it followed the device appearance instead.
        .background {
            ConcentricRectangle(corners: .concentric, isUniform: true)
                .fill(colors.surface)
        }
        .overlay {
            ConcentricRectangle(corners: .concentric, isUniform: true)
                .stroke(colors.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func rowContextPreview(flight: Flight, colors: ThemeColors) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(flight.flightNumber)
                .appFont(.flightNumber, lineLimit: .exactly(1))
                .foregroundStyle(colors.text)

            HStack(alignment: .top, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(flight.departure.code)
                        .appFont(.airportCode, lineLimit: .exactly(1))
                        .foregroundStyle(colors.text)
                    Text(flight.departure.city)
                        .appFont(.placeMeta, lineLimit: .exactly(1))
                        .foregroundStyle(colors.textSecondary)
                }

                Spacer(minLength: AppSpacing.md)

                Image(systemName: "airplane")
                    .font(AppTypography.mono(.caption, weight: .semibold))
                    .foregroundStyle(colors.primary)

                Spacer(minLength: AppSpacing.md)

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text(flight.arrival.code)
                        .appFont(.airportCode, lineLimit: .exactly(1))
                        .foregroundStyle(colors.text)
                    Text(flight.arrival.city)
                        .appFont(.placeMeta, lineLimit: .exactly(1))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            HStack(spacing: AppSpacing.xs) {
                statusDot(for: flight.status)
                Text(flight.status.displayName)
                    .appFont(.flightStatus, lineLimit: .exactly(1))
                    .foregroundStyle(colors.text)
            }
        }
        .padding(AppSpacing.md)
        .frame(width: 300)
        // The context-menu preview is hosted by the system, which paints it
        // against the DEVICE appearance. It must bring its own opaque surface or
        // it inherits the wrong ground. `.regularMaterial` did exactly that.
        .background(colors.surface)
    }
    
    private func getStatusColor(for status: FlightStatus) -> Color {
        switch status {
        case .boarding: return themeManager.currentTheme.colors.statusBoarding
        case .departed: return themeManager.currentTheme.colors.statusDeparted
        case .inAir: return themeManager.currentTheme.colors.statusInAir
        case .landed: return themeManager.currentTheme.colors.statusLanded
        case .delayed: return themeManager.currentTheme.colors.statusDelayed
        case .cancelled: return themeManager.currentTheme.colors.statusCancelled
        }
    }

}


/// NO LONGER APPLIED. Nothing constructs this.
///
/// It existed to make the hand-rolled bar the only bar on screen: one runloop
/// after layout it walked `superview.superview` (the `.compositingGroup()` that
/// used to sit under the TabView) down to the `UITabBarController` SwiftUI backs
/// a default-styled TabView with, cleared its backgrounds, and sent the tab bar
/// `removeFromSuperview()`. That is precisely why the app did not look like
/// Liquid Glass — the real glass bar was built every launch and then destroyed.
///
/// Kept, unused, because this app is scoped and things get switched back. Its
/// `Coordinator` also killed the cross-fade between tabs (a zero-duration
/// transition); with the system bar back, tab changes animate the system way.
fileprivate struct TabViewHelper: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        DispatchQueue.main.async {
            guard let compostingGroup = view.superview?.superview else { return }
            guard let swiftUIWrapperUITabView = compostingGroup.subviews.last else { return }
            
            if let tabBarController = swiftUIWrapperUITabView.subviews.first?.next as? UITabBarController {
                /// Clearing Backgrounds for liquid glass effect
                tabBarController.view.backgroundColor = .clear
                tabBarController.viewControllers?.forEach {
                    $0.view.backgroundColor = .clear
                }
                
                tabBarController.delegate = context.coordinator
                
                /// Remove default tab bar to use custom liquid glass one
                tabBarController.tabBar.removeFromSuperview()
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) { }
    
    class Coordinator: NSObject, UITabBarControllerDelegate, UIViewControllerAnimatedTransitioning {
        func tabBarController(_ tabBarController: UITabBarController, animationControllerForTransitionFrom fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            return self
        }
        
        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            return .zero
        }
        
        func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
            guard let destinationView = transitionContext.view(forKey: .to) else { return }
            let containerView = transitionContext.containerView
            
            containerView.addSubview(destinationView)
            transitionContext.completeTransition(true)
        }
    }
}

// MARK: - Custom Menu View

struct CustomMenuView<Label: View, Content: View>: View {
    var style: CustomMenuStyle = .glass
    var isHapticsEnabled: Bool = true
    @ViewBuilder var label: Label
    @ViewBuilder var content: Content
    /// View Properties
    @State private var haptics: Bool = false
    @State private var isExpanded: Bool = false
    /// For Zoom transition
    @Namespace private var namespace
    
    var body: some View {
        Button {
            if isHapticsEnabled {
                haptics.toggle()
            }
            
            isExpanded.toggle()
        } label: {
            label
                .matchedTransitionSource(id: "MENUCONTENT", in: namespace)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .popover(isPresented: $isExpanded) {
            PopOverHelper {
                content
            }
            .navigationTransition(.zoom(sourceID: "MENUCONTENT", in: namespace))
        }
        .sensoryFeedback(.selection, trigger: haptics)
    }
}

fileprivate struct PopOverHelper<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var isVisible: Bool = false
    
    var body: some View {
        content
            .opacity(isVisible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(0.1))
                withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                    isVisible = true
                }
            }
            .presentationCompactAdaptation(.popover)
    }
}

/// Menu Style
enum CustomMenuStyle: String, CaseIterable {
    case glass = "Glass"
    case glassProminent = "Glass Prominent"
}

// MARK: - Boarding Pass Menu Content

struct BoardingPassMenuContent: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var unifiedService = UnifiedBoardingPassService.shared
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingPicker = false
    
    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.md) {
            // "Add a Flight" rather than "Scan Boarding Pass": scanning is now
            // one of two ways in, and a title that names only the first one
            // makes the second look like a fallback for when the app is broken.
            Text("Add a Flight")
                .appFont(.bodyBold, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.text)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: AppSpacing.sm) {
                Button {
                    isShowingPicker = true
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "camera.viewfinder")
                            .font(AppTypography.mono(.body, weight: .semibold))

                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Scan a pass")
                                .appFont(.bodyBold, lineLimit: .exactly(1))
                            Text("Camera or photos")
                                .appFont(.footnote, lineLimit: .exactly(1))
                        }

                        Spacer(minLength: AppSpacing.xs)

                        Image(systemName: "chevron.right")
                            .font(AppTypography.mono(.caption, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.xs)
                }
                // `.glassProminent` + `.tint` instead of `.foregroundColor(.white)`
                // over a `primary` fill: white on dark `primary` (0x4DA3FF) is
                // 2.6:1 and fails AA. The system picks a legible label for us.
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.colors.primary)
                .disabled(unifiedService.isProcessing)

                // The floor under the whole app. A bad photo, no network or a
                // dead proxy used to mean the flight could not be added AT ALL;
                // typing it always works. Quieter than the scan button — plain
                // `.glass`, no fill — because scanning is still the fast path,
                // but not hidden behind a menu: it is the recovery from the
                // failure the row above can produce.
                Button {
                    startManualEntry()
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "square.and.pencil")
                            .font(AppTypography.mono(.body, weight: .semibold))

                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Enter manually")
                                .appFont(.bodyBold, lineLimit: .exactly(1))
                            Text("Type the flight in")
                                .appFont(.footnote, lineLimit: .exactly(1))
                        }

                        Spacer(minLength: AppSpacing.xs)

                        Image(systemName: "chevron.right")
                            .font(AppTypography.mono(.caption, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.xs)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .tint(theme.colors.primary)
                // A scan in flight owns the confirmation sheet the moment it
                // lands, so a second route to the same sheet stays shut until
                // it is done.
                .disabled(unifiedService.isProcessing)

                if unifiedService.isProcessing {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .tint(theme.colors.primary)

                        Text("Scanning\u{2026}")
                            .appFont(.placeMeta, lineLimit: .exactly(1))
                            .foregroundStyle(theme.colors.textSecondary)

                        Spacer(minLength: 0)
                    }
                }

                // A scan failed only if it produced NO pass. Testing `error != nil`
                // reported failure on every successful scan of a booking
                // confirmation: the barcode step always errors for a pass that
                // was never checked in, and that error outlived the fallback
                // that went on to read the flight correctly.
                if unifiedService.lastResult?.data == nil,
                   unifiedService.lastResult?.error != nil {
                    // Inline, not a filled 10%-error banner. A tinted block reads
                    // as warm mud on navy and as a Post-it on paper; an icon plus
                    // `error`-coloured text reads correctly in both.
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(AppTypography.mono(.caption, weight: .bold))
                            .foregroundStyle(theme.colors.error)

                        Text("Scan failed")
                            .appFont(.placeMeta, lineLimit: .exactly(1))
                            .foregroundStyle(theme.colors.error)

                        Spacer(minLength: AppSpacing.xs)

                        Button {
                            isShowingPicker = true
                        } label: {
                            Text("Retry")
                                .appFont(.verdictLabel, lineLimit: .exactly(1))
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .tint(theme.colors.primary)
                    }
                }
            }

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .appFont(.bodySmall, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xs)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(AppSpacing.md)
        // Width only. The old `height: 180` clipped the popover the moment
        // Dynamic Type went past Large.
        .frame(width: 300)
        .photosPicker(isPresented: $isShowingPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newPhoto in
            if let newPhoto = newPhoto {
                processSelectedPhoto(newPhoto)
            }
        }
    }
    
    /// Manual entry is the confirmation sheet with an EMPTY pass in it.
    ///
    /// It reports on the same channel a scan does, so it inherits the whole
    /// downstream path unchanged: `ContentView` parks the pass while this sheet
    /// leaves, presents `BoardingPassConfirmationView`, and on save builds the
    /// `Flight` and stores it. There is no second form and no second save path
    /// — the only difference between a scan and a typed flight is whether the
    /// fields arrive filled.
    ///
    /// It does NOT call `dismiss()`, and that is deliberate. The observer parks
    /// the pass and takes this sheet down ITSELF, then puts the confirmation up
    /// from `onDismiss` — an ordering that is defined rather than hoped for.
    /// Dismissing from here instead races that: the observer's hop to the main
    /// actor can land after the presentation binding has already gone false, in
    /// which case the pass takes the "nothing is up, present immediately" branch
    /// and asks one host to present a second sheet while the first is still
    /// leaving. Presenting into a dismissal is a known way to lose a sheet.
    private func startManualEntry() {
        let empty = BoardingPassData()
        print("✍️ Manual entry requested — opening an empty pass")
        NotificationCenter.default.post(
            name: NSNotification.Name("BoardingPassScanned"),
            object: empty
        )
    }

    private func processSelectedPhoto(_ photo: PhotosPickerItem) {
        Task {
            do {
                guard let imageData = try await photo.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: imageData) else {
                    print("❌ Failed to load selected image")
                    return
                }
                
                print("📸 Processing boarding pass image...")
                
                if let boardingPassData = await unifiedService.parseImage(uiImage) {
                    print("✅ OCR completed successfully:", boardingPassData.summary)
                    
                    // Post notification to main view to show confirmation and close menu
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("BoardingPassScanned"),
                            object: boardingPassData
                        )
                        print("📋 Posted notification for boarding pass: \(boardingPassData.summary)")
                        dismiss() // Close the menu
                    }
                } else {
                    print("❌ OCR failed to extract boarding pass data")
                }
                
            } catch {
                print("❌ Error loading image: \(error.localizedDescription)")
                print("❌ Error processing photo:", error)
            }
        }
    }
    
    private func handleBoardingPassScanned(_ boardingPassData: BoardingPassData) async {
        print("🎫 Boarding pass confirmed in menu:", boardingPassData.summary)
        
        // Post a notification to handle this in the parent view
        NotificationCenter.default.post(
            name: NSNotification.Name("BoardingPassScanned"), 
            object: boardingPassData
        )
    }
}

// MARK: - Flight Filter Segmented Control
/// A glass capsule rather than an opaque radius-25 pill. The sheet's chrome is
/// glass everywhere else; an opaque control inside it was a second, unrelated
/// vocabulary on the same screen.
struct FlightFilterSegmentedControl: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedFilter: FlightFilter
    @Namespace private var animation

    var body: some View {
        let theme = themeManager.currentTheme

        return SkyLineGlassPanel(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(FlightFilter.allCases, id: \.self) { filter in
                    segment(filter, theme: theme)
                }
            }
            .padding(AppSpacing.xs)
            .skylineGlassCapsule(theme: theme)
        }
    }

    @ViewBuilder
    private func segment(_ filter: FlightFilter, theme: AppTheme) -> some View {
        let isSelected = selectedFilter == filter

        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                selectedFilter = filter
            }
        } label: {
            Text(filter.rawValue.uppercased())
                .appFont(.verdictLabel, lineLimit: .exactly(1))
                .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm + 2)
                .background {
                    if isSelected {
                        // One token at two alphas, not two colours: `primary` is a
                        // dark ink on light and a light ink on dark, so a fixed
                        // alpha would be a bruise in one theme and invisible in
                        // the other. Mirrors `TabBarItem` exactly.
                        Capsule(style: .continuous)
                            .fill(theme.colors.primary.opacity(theme == .light ? 0.12 : 0.20))
                            .matchedGeometryEffect(id: "flightFilter", in: animation)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(filter.rawValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Empty Flight Filter State
// MARK: - Flight Empty States
/// The flight surfaces' empty states, collapsed from two bespoke blocks into one.
///
/// This is deliberately a thin echo of `PlaceLogEmptyStateView` — same glyph well,
/// same type ladder, same spacing — rather than a new visual language. The correct
/// fix is two more cases on `PlaceLogEmptyState`, but that enum lives in a file
/// this pass does not own.
struct FlightsEmptyStateView: View {
    enum Kind {
        case noFlights
        case noUpcoming
        case noPast

        var systemImage: String {
            switch self {
            case .noFlights: return "airplane"
            case .noUpcoming: return "calendar"
            case .noPast: return "clock.arrow.circlepath"
            }
        }

        var title: String {
            switch self {
            case .noFlights: return "No flights yet"
            case .noUpcoming: return "Nothing booked"
            case .noPast: return "Nothing flown yet"
            }
        }

        var message: String {
            switch self {
            case .noFlights:
                return "Scan a boarding pass and SkyLine will draw the route on the globe."
            case .noUpcoming:
                return "Flights you have not taken yet will show up here."
            case .noPast:
                return "Once a flight has departed it moves here."
            }
        }
    }

    @EnvironmentObject var themeManager: ThemeManager
    let kind: Kind

    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 44
    @ScaledMetric(relativeTo: .largeTitle) private var glyphWell: CGFloat = 88

    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: AppSpacing.md) {
            Image(systemName: kind.systemImage)
                .font(.system(size: glyphSize, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.colors.textSecondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: glyphWell, height: glyphWell)
                // Tinted glass rather than a filled circle: on light the tint is a
                // faint blue wash on near-white, on dark it lifts off the navy.
                // A flat fill would need two different colours to do the same job.
                .skylineGlass(
                    .card,
                    in: Circle(),
                    tint: theme.colors.primary.opacity(0.20),
                    theme: theme
                )

            VStack(spacing: AppSpacing.sm) {
                Text(kind.title)
                    .appFont(.headline)
                    .foregroundStyle(theme.colors.text)
                    .multilineTextAlignment(.center)

                Text(kind.message)
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    SkyLineBottomBarView(
        activeTab: .constant(.primary),
        selectedDetent: .constant(.fraction(0.3))
    )
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
        .environmentObject(AuthenticationService.shared)
}


// MARK: - Perforation Line
/// A single horizontal rule, stroked with a dash pattern. A `Shape` rather than a
/// hand-drawn `Path` in a `GeometryReader` so the dash phase is resolution
/// independent and the stroke colour comes from the palette at the call site.
private struct PassPerforationLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
