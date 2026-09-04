//
//  SkyLineApp.swift
//  SkyLine
//
//  Created by Priyanshu Madan on 8/24/25.
//

import SwiftUI
import CloudKit
import AuthenticationServices

/// Whether the first-run onboarding flow runs at all.
///
/// OFF because the app is scoped back to its original idea: scan a boarding
/// pass, store the flight, draw its path on the globe. Onboarding's third page
/// hands off to `FirstRunDetectionView`, which scans the user's WHOLE photo
/// library looking for places — nothing to do with boarding passes, and not
/// something to run on first launch of a flight logger.
///
/// Nothing is deleted: `OnboardingView`, `OnboardingViewModel`, `OnboardingPage`
/// and `FirstRunDetectionView` all still exist and still compile, and
/// `OnboardingState`'s two flags are untouched in UserDefaults. This constant
/// gates the only two places `showOnboarding` can become true — the first-run
/// read below, and the `.skyLineOnboardingRequested` re-entry — so flipping it
/// to `true` restores the flow exactly as it was.
private let skyLineFirstRunOnboardingEnabled = false

@main
struct SkyLineApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var flightStore = FlightStore()
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var placeStore = PlaceStore.shared
    @State private var isGlobeReady = false

    // MARK: First run
    //
    // Read once, from UserDefaults, so the very first frame after sign-in is
    // already the right one. `OnboardingState` is a plain namespace rather than
    // a member of the (main-actor isolated) view model precisely so it can be
    // touched from a `@State` initialiser.
    @State private var showOnboarding = skyLineFirstRunOnboardingEnabled && !OnboardingState.hasSeenOnboarding
    @State private var onboardingEntryPage: OnboardingPage = .premise
    /// The globe has reported ready. Kept separately from `isGlobeReady`, which
    /// is when we ACT on it. See `revealGlobeIfReady()`.
    @State private var didReceiveGlobeReady = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    switch authService.authenticationState {
                    case .authenticated:
                        ContentView(isGlobeReady: $isGlobeReady)
                            .environmentObject(themeManager)
                            .environmentObject(flightStore)
                            .environmentObject(authService)
                            .environmentObject(placeStore)
                            .onAppear {
                                // Sync trip data when user is authenticated
                                Task {
                                    await TripStore.shared.syncIfNeeded()
                                    await placeStore.syncIfNeeded()

                                    // Seed initial airline data if needed
                                    await AirlineService.shared.seedInitialAirlines()

                                    // Place/Visit record types have to exist in
                                    // CloudKit before the first save, and the
                                    // one-way import backfills places from the
                                    // Trip/TripEntry/Flight records the user
                                    // already has - so a returning user does not
                                    // open the new app to an empty map.
                                    CountryLocator.shared.preload()
                                    await PlaceSchemaService.shared.initializePlaceSchema()

                                    // The import must not start before the
                                    // flights it reads have loaded. FlightStore
                                    // fetches asynchronously, so calling this
                                    // with flightStore.flights straight away is
                                    // a race: on a cold cache the flight half
                                    // of the backfill silently imports nothing,
                                    // and whether it works depends on whether
                                    // the local cache happened to be warm.
                                    await flightStore.syncIfNeeded()
                                    await PlaceImportService.shared.runIfNeeded(
                                        flights: flightStore.flights)
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                                // Sync when app comes to foreground
                                Task {
                                    await TripStore.shared.syncIfNeeded()
                                    await flightStore.syncIfNeeded()
                                    await placeStore.syncIfNeeded()
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GlobeReady"))) { _ in
                                // The globe has finished loading. Whether the
                                // splash lifts right now is a separate question.
                                didReceiveGlobeReady = true
                                revealGlobeIfReady()
                            }

                    case .authenticating:
                        // Show loading screen while checking existing authentication
                        AppLoadingView()
                            .environmentObject(themeManager)

                    case .unauthenticated, .error:
                        AuthenticationView()
                            .environmentObject(themeManager)
                            .environmentObject(authService)
                    }
                }

                // Splash overlay - show until globe is ready
                if authService.authenticationState.isAuthenticated && !isGlobeReady {
                    AppLoadingView()
                        .environmentObject(themeManager)
                        .transition(.opacity)
                        .zIndex(999)
                }

                // First-run onboarding.
                //
                // AFTER sign-in, never before: it is gated on
                // `.isAuthenticated`, so an unauthenticated launch still lands
                // on AuthenticationView exactly as it did.
                //
                // Layered ON TOP of ContentView rather than replacing it, so the
                // WebKit globe boots while the user is reading. The GlobeReady
                // notification therefore still arrives on its normal schedule
                // and the user lands on a globe that is already spinning instead
                // of on a loading screen.
                // `showOnboarding` can only be true when
                // `skyLineFirstRunOnboardingEnabled` is — see the two sites that
                // set it. The view below is intact and unreferenced-but-alive.
                if authService.authenticationState.isAuthenticated && showOnboarding {
                    OnboardingView(startingAt: onboardingEntryPage) {
                        // `App` is not a `View`, so there is no environment here
                        // to read accessibilityReduceMotion from.
                        let animation: Animation? = UIAccessibility.isReduceMotionEnabled
                            ? nil
                            : .easeInOut(duration: 0.35)
                        withAnimation(animation) {
                            showOnboarding = false
                        }
                    }
                    .environmentObject(themeManager)
                    .environmentObject(placeStore)
                    .environmentObject(flightStore)
                    .environmentObject(authService)
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .task {
                // Before anything else touches CloudKit, so the wipe is not
                // racing a sync that would write records straight back.
                #if DEBUG
                if DebugFlags.wipeAllDataOnLaunch {
                    await DebugDataWipe.wipeEverything()
                }
                #endif
            }
            .onAppear {
                // Enable CloudKit background sync
                // `enableBackgroundSync()` deliberately NOT called.
                //
                // It saved a CKQuerySubscription with a fresh random id on every
                // single launch, accumulating subscriptions in the user's account
                // for push notifications this app never registers to receive.
                // `aps-environment` is gone from the entitlements with it.
                
                // Configure immersive navigation and status bars
                configureImmersiveAppearance(for: themeManager.currentTheme)
            }
            .onChange(of: themeManager.currentTheme) { theme in
                // Update bar appearance when theme changes
                configureImmersiveAppearance(for: theme)
            }
            .onReceive(NotificationCenter.default.publisher(for: .skyLineOnboardingRequested)) { note in
                // Scoped to boarding-pass scanning: the flow is off, so a
                // re-entry request is ignored rather than raising an overlay
                // that will not draw. Without this guard `showOnboarding` would
                // go true, `onChange` would pull `isGlobeReady` down, and the
                // sheet would never come back up.
                guard skyLineFirstRunOnboardingEnabled else { return }
                // Re-entry for the user who skipped. Posted by
                // `OnboardingState.requestPresentation(startingAt:)`, which any
                // later surface - the place log's empty state, the profile - can
                // call so skipping the tour never strands them without photo
                // permission or first-run detection.
                onboardingEntryPage = (note.object as? OnboardingPage) ?? .detect
                showOnboarding = true
            }
            .onChange(of: showOnboarding) { _, isShowing in
                if isShowing {
                    // ContentView's bottom sheet is a modal presentation and
                    // sits above every zIndex in this stack, so it has to come
                    // down before the flow is presented over it.
                    isGlobeReady = false
                } else {
                    revealGlobeIfReady()
                }
            }
        }
    }

    // MARK: - Splash Reveal

    /// Lifts the splash once the globe has reported ready and nothing is
    /// covering the app.
    ///
    /// `isGlobeReady` drives two things: the splash overlay, and the presentation
    /// of ContentView's bottom sheet. A `.sheet` is a modal presentation that
    /// renders ABOVE every zIndex in this stack, so letting it rise during
    /// onboarding would slide the tab bar over the first-run flow. Holding this
    /// false for the duration keeps ContentView mounted - the WebView keeps
    /// loading, GlobeReady still arrives - while the sheet stays down.
    ///
    /// With no onboarding on screen this is the original behaviour unchanged:
    /// the notification arrives, the splash fades on the same 0.5s easeOut.
    private func revealGlobeIfReady() {
        guard didReceiveGlobeReady, !showOnboarding, !isGlobeReady else { return }
        withAnimation(.easeOut(duration: 0.5)) {
            isGlobeReady = true
        }
    }
    
    // MARK: - Immersive UI Configuration
    
    private func configureImmersiveAppearance(for theme: AppTheme) {
        // Configure Navigation Bar Appearance
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor(theme.colors.surface)
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(theme.colors.text),
            .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(theme.colors.text),
            .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .bold)
        ]
        
        // Apply to all navigation bar states
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        
        // Configure Tab Bar Appearance
        //
        // `configureWithDefaultBackground()`, NOT `configureWithOpaqueBackground()`.
        //
        // The opaque call is an explicit instruction to replace the bar's
        // material with a flat fill, and it was written when the system bar was
        // being hidden anyway and a bar was hand-drawn in its place. Once the
        // real bar came back, that line was still overriding it - so iOS 26
        // rendered Liquid Glass and this immediately painted a solid dark
        // rectangle over it. That rectangle is what read as "a capsule inside
        // another capsule". The default background keeps the system material.
        let tabBarAppearance = UITabBarAppearance()
        // Transparent, not default. `configureWithDefaultBackground()` gives the
        // bar its own full-width background container, and iOS 26 then draws the
        // floating glass tab group INSIDE that - which is the wide dark rectangle
        // wrapped around a capsule. Transparent leaves only the floating group.
        tabBarAppearance.configureWithTransparentBackground()

        // The app's face, scaled. `monospacedSystemFont(ofSize: 10)` was SF Mono
        // - not the face the rest of the app uses - and a hard 10pt that ignored
        // Dynamic Type entirely.
        let labelFont = UIFont(name: "GeistMono-Medium", size: 10)
            ?? UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let scaledLabelFont = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: labelFont)

        // Configure tab bar item appearance
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(theme.colors.textSecondary)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(theme.colors.textSecondary),
            .font: scaledLabelFont
        ]
        
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(theme.colors.primary)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(theme.colors.primary),
            .font: scaledLabelFont
        ]
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Configure Status Bar Style for all windows
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = theme == .light ? .light : .dark
            }
        }
    }
}

// MARK: - App Loading View
//
// The splash. Seven layers, each on its own schedule, lifted from the design's
// 1290x2796 artboard and its CSS keyframes.
//
// Drawn NATIVELY rather than blitted from the `SplashSky` / `SplashGlobe`
// imagesets, and that is a deliberate departure from the brief. Both PNGs are
// flattened composites of layers this animation has to move independently: the
// starfield lives inside the sky, and the halo - which breathes on its own
// 4200ms loop - lives inside the globe. Neither can be separated back out of a
// raster. The artwork itself is pure vector at these exact numbers, every one of
// which was measured back off the PNGs before a line of this was written:
//
//   sphere   perfect circle, centre (645, 2140), r 900, one flat fill:
//            #000011 dark / #EEF2FA light == `colors.globeBackground`, exactly
//   halo     a disc of r 970 under a 60px Gaussian, tinted #4DA3FF at 40%
//            (== `colors.globeAtmosphere`) dark / #DCE2EF (== `colors.border`)
//            light, held at the SVG's static 0.55 in the export
//   stars    167 of them in three classes - 107 at r1.6/0.18, 43 at r2.4/0.38,
//            17 at r3.6/1.0 - all inside artboard y 0...1353
//
// so this is not an approximation of the PNGs, it is the drawing they were
// rasterised from. Two further things fall out of it for free: the splash now
// reads the theme the user picked IN THE APP rather than the asset catalog's
// `luminosity` trait, and nothing has to be decoded off disk on the launch path.
//
// The imagesets are left in place and unreferenced.

// MARK: Timing

/// A CSS `cubic-bezier(x1, y1, x2, y2)` easing curve, evaluated the way a
/// browser evaluates it: solve x(u) = t for the curve parameter u, then read y.
///
/// SwiftUI's `.timingCurve` takes the same four numbers and would be the obvious
/// tool, but it animates BETWEEN VIEW STATES on a wall clock. Every schedule here
/// runs off one shared frame clock instead (see `SplashClock`, which explains
/// why), so the curves have to be sampled directly rather than handed to
/// `withAnimation`.
struct SplashEasing {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    /// CSS `ease` - the default, and not the same curve as SwiftUI's `.easeInOut`.
    static let ease = SplashEasing(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    /// CSS `ease-in-out`.
    static let easeInOut = SplashEasing(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    static let globeRise = SplashEasing(x1: 0.22, y1: 0.8, x2: 0.26, y2: 1)
    static let markRise = SplashEasing(x1: 0.22, y1: 0.9, x2: 0.24, y2: 1)
    static let arcDraw = SplashEasing(x1: 0.3, y1: 0, x2: 0.2, y2: 1)

    func callAsFunction(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }

        // Newton-Raphson converges in three or four steps for all five curves
        // above. Bisection is only insurance against a flat spot in the slope.
        var u = t
        for _ in 0..<8 {
            let error = Self.axis(u, x1, x2) - t
            if abs(error) < 1e-6 { return Self.axis(u, y1, y2) }
            let slope = Self.slope(u, x1, x2)
            if abs(slope) < 1e-6 { break }
            u -= error / slope
        }

        var low = 0.0
        var high = 1.0
        u = t
        for _ in 0..<32 {
            let x = Self.axis(u, x1, x2)
            if abs(x - t) < 1e-6 { break }
            if x < t { low = u } else { high = u }
            u = (low + high) / 2
        }
        return Self.axis(u, y1, y2)
    }

    /// One axis of a unit cubic Bezier: P0 = 0, P3 = 1.
    private static func axis(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }

    private static func slope(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
    }
}

/// The clock every splash instance measures from.
///
/// Two problems, one clock.
///
/// **A cold launch raises `AppLoadingView` twice** - once while authentication
/// resolves, once as the overlay that waits on the WebKit globe - and those are
/// two different view identities in two different branches of the root ZStack.
/// Given per-instance state each would restart the 1500ms globe rise from zero
/// and the sphere would visibly drop back down mid-flight.
///
/// **The animation must play on frames the user actually sees.** This was
/// measured, not assumed: a launch recording of the first build showed roughly
/// 0.6s between SwiftUI evaluating this body and the first frame reaching the
/// screen, and two further stalls of 0.7s and 0.4s after that - the system
/// launch screen covering all of it. On a plain wall clock the globe finished
/// rising behind the launch screen and the wordmark's first visible frame was
/// already half faded in.
///
/// So this is not a wall clock. It ACCUMULATES the gaps between frames, capping
/// each one, exactly the way a game loop clamps its delta:
///
///   elapsed += min(now - lastFrame, maxStep)
///
/// Normal 60Hz pacing is ~16ms and passes through untouched, so the animation
/// runs at true speed whenever the app is drawing. A 700ms stall advances it by
/// 67ms instead of 700, so the motion is paused rather than skipped and every
/// frame the user is shown is a real step of it. That is the right trade for a
/// launch animation: better to see the globe rise a little late than to be
/// handed the end of it.
@MainActor
enum SplashClock {
    private static var accumulated: TimeInterval = 0
    private static var lastTick: Date?
    private static var onScreen = 0
    private static var hiddenSince: Date?

    /// The most one frame may advance the animation. 67ms is four frames at
    /// 60Hz: any real frame interval, including a 30Hz or 20Hz stretch, passes
    /// through whole, and only an actual stall is clamped.
    private static let maxStep: TimeInterval = 1.0 / 15.0

    /// Seconds into the animation at `date`, which must be the timeline's own
    /// date rather than `Date()` - that is what makes this a frame clock.
    ///
    /// Advancing on the DATE rather than on the call also makes it safe to call
    /// twice in one frame: on the transition frame both splash instances are
    /// evaluated, both see the same date, and the second one adds nothing.
    static func elapsed(at date: Date) -> Double {
        rewindIfStale(now: date)

        if let lastTick {
            let delta = date.timeIntervalSince(lastTick)
            if delta > 0 { accumulated += min(delta, maxStep) }
        }
        lastTick = date

        return accumulated
    }

    static func splashAppeared() {
        onScreen += 1
        hiddenSince = nil
    }

    static func splashDisappeared() {
        onScreen = max(0, onScreen - 1)
        if onScreen == 0 { hiddenSince = Date() }
    }

    /// Starts the whole thing over once no splash has been on screen for a
    /// moment, so a genuine second launch - sign out, sign back in - plays in
    /// full instead of opening on a settled frame.
    private static func rewindIfStale(now: Date) {
        guard onScreen == 0,
              let hidden = hiddenSince,
              now.timeIntervalSince(hidden) > 0.75
        else { return }
        accumulated = 0
        lastTick = nil
        hiddenSince = nil
    }
}

// MARK: Frame

/// Every animated quantity in the splash, resolved for one instant.
///
/// Pulling them out of the view tree keeps the seven schedules in one readable
/// place and means the Reduce Motion path is a value, not a second code path.
struct SplashFrame {
    /// Seconds since the animation began. `nil` when Reduce Motion has frozen it,
    /// which is what stops the starfield twinkling.
    var elapsed: Double?

    /// `sl-fade 500ms ease` on the star group. The GROUND does not fade - it is a
    /// plain `background` on the artboard in the design, and starting on the real
    /// page colour is also what keeps the very first frame from flashing.
    var starsOpacity: Double
    /// `sl-globe-rise 1500ms cubic-bezier(0.22, 0.8, 0.26, 1)`, 0 -> 1.
    var globeRise: Double
    var globeOpacity: Double
    /// `sl-fade 500ms ease 60ms` on the sphere, inside the rising group.
    var sphereOpacity: Double
    /// `sl-breathe 4200ms ease-in-out 900ms infinite`, 0.45 <-> 0.75.
    var haloOpacity: Double
    /// `sl-rise 1000ms cubic-bezier(0.22, 0.9, 0.24, 1) 300ms`, 0 -> 1. Carries
    /// the arc AND the wordmark - they are one column in the design.
    var markRise: Double
    var markOpacity: Double
    /// Letter-spacing in em. 0.26 -> -0.01.
    ///
    /// The brief quotes -0.06em as the wordmark's tracking "at rest" and -0.01em
    /// as the keyframe's end. Both are in the CSS, and the animation wins: it
    /// carries `animation-fill-mode: both`, which it has to, or the opacity would
    /// snap back to 0 the moment it finished. -0.06em is the declaration the
    /// filled animation overrides, so -0.01em is what actually rests on screen.
    var trackingEm: Double
    /// `sl-draw 1200ms cubic-bezier(0.3, 0, 0.2, 1) 900ms` - stroke-dashoffset
    /// 1 -> 0 over a path of unit length, which is `.trim(from: 0, to:)`.
    var arcProgress: Double
    /// `sl-fade 300ms ease 850ms`.
    var departureOpacity: Double
    /// `sl-fade 300ms ease 2050ms`. Lands as the arc arrives.
    var arrivalOpacity: Double

    /// The design with every animation removed. Reduce Motion gets this, and it
    /// is also - to the byte - what the still PNG export captured: the halo sits
    /// at the SVG's own static `opacity="0.55"` rather than anywhere on the
    /// breathe loop.
    static let resting = SplashFrame(
        elapsed: nil,
        starsOpacity: 1,
        globeRise: 1,
        globeOpacity: 1,
        sphereOpacity: 1,
        haloOpacity: 0.55,
        markRise: 1,
        markOpacity: 1,
        trackingEm: -0.01,
        arcProgress: 1,
        departureOpacity: 1,
        arrivalOpacity: 1
    )
}

extension SplashFrame {
    init(elapsed: Double) {
        self.init(
            elapsed: elapsed,
            starsOpacity: Self.run(elapsed, delay: 0, duration: 0.5, easing: .ease),
            globeRise: Self.run(elapsed, delay: 0, duration: 1.5, easing: .globeRise),
            globeOpacity: Self.run(elapsed, delay: 0, duration: 1.5, easing: .globeRise),
            sphereOpacity: Self.run(elapsed, delay: 0.06, duration: 0.5, easing: .ease),
            haloOpacity: Self.loop(elapsed, delay: 0.9, duration: 4.2, easing: .easeInOut, low: 0.45, high: 0.75),
            markRise: Self.run(elapsed, delay: 0.3, duration: 1.0, easing: .markRise),
            markOpacity: Self.run(elapsed, delay: 0.3, duration: 1.0, easing: .markRise),
            trackingEm: 0.26 + (-0.01 - 0.26) * Self.run(elapsed, delay: 0.3, duration: 1.0, easing: .markRise),
            arcProgress: Self.run(elapsed, delay: 0.9, duration: 1.2, easing: .arcDraw),
            departureOpacity: Self.run(elapsed, delay: 0.85, duration: 0.3, easing: .ease),
            arrivalOpacity: Self.run(elapsed, delay: 2.05, duration: 0.3, easing: .ease)
        )
    }

    /// Opacity of one of the seventeen twinkling stars.
    ///
    /// `sl-twinkle` is `0%,100% { 0.22 } 50% { 1 }`, and CSS applies the timing
    /// function between each pair of keyframes rather than across the whole
    /// cycle - so each half is eased independently, not sampled off one curve.
    func twinkle(_ index: Int) -> Double {
        guard let elapsed else { return 1 }
        let duration = SplashStars.twinkleDurations[index % SplashStars.twinkleDurations.count]
        let delay = SplashStars.twinkleDelays[index % SplashStars.twinkleDelays.count]
        return Self.loop(elapsed, delay: delay, duration: duration, easing: .easeInOut, low: 0.22, high: 1)
    }

    /// One run of a CSS animation with `animation-fill-mode: both`: clamped
    /// before the delay elapses and after the duration does.
    private static func run(_ elapsed: Double, delay: Double, duration: Double, easing: SplashEasing) -> Double {
        easing(min(max((elapsed - delay) / duration, 0), 1))
    }

    /// A `0%,100% -> low, 50% -> high` pair repeating forever, `both` filled.
    private static func loop(
        _ elapsed: Double,
        delay: Double,
        duration: Double,
        easing: SplashEasing,
        low: Double,
        high: Double
    ) -> Double {
        let time = elapsed - delay
        guard time > 0 else { return low }
        let phase = time.truncatingRemainder(dividingBy: duration) / duration
        return phase < 0.5
            ? low + (high - low) * easing(phase * 2)
            : high + (low - high) * easing((phase - 0.5) * 2)
    }
}

// MARK: Artboard

/// Maps the design's 1290x2796 artboard onto the real screen the way the PNG it
/// replaces was mapped: `aspectRatio(contentMode: .fill)`, centre-cropped.
///
/// `max` rather than `min` is the whole of `.fill` - the artboard always covers
/// the screen and spills off two of its edges. Everything in the design sits
/// inside the middle 70% vertically and 80% horizontally for that reason.
struct SplashArtboard {
    static let width: CGFloat = 1290
    static let height: CGFloat = 2796

    /// The design's wordmark size, in artboard px. Every other measurement in
    /// the mark is expressed as a multiple of it so the arc, the two dots and
    /// the type all grow together under Dynamic Type.
    static let wordmarkSize: CGFloat = 128

    let scale: CGFloat
    let origin: CGPoint

    init(size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            scale = 0
            origin = .zero
            return
        }
        let fill = max(size.width / Self.width, size.height / Self.height)
        scale = fill
        origin = CGPoint(
            x: (size.width - Self.width * fill) / 2,
            y: (size.height - Self.height * fill) / 2
        )
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func length(_ value: CGFloat) -> CGFloat { value * scale }
}

// MARK: Starfield

/// The design's own starfield, verbatim.
///
/// These are the 167 circles from the artboard's SVG, not a fresh sample, so the
/// sky is the same sky the shipped PNG showed - the only thing that changed is
/// that seventeen of them now move. A seeded PRNG would also be repeatable
/// between launches, but it would be a DIFFERENT sky, and there is no reason to
/// redraw one that was already designed.
///
/// Stored as interleaved x, y in artboard coordinates. `Int16` keeps the literal
/// small and keeps the type checker off it.
enum SplashStars {
    /// r 1.6, opacity 0.18, static.
    static let dimXY: [Int16] = [
        770, 837, 270, 541, 1281, 165, 495, 85, 956, 178, 189, 76, 47, 948, 494, 837, 1019,
        875, 741, 1161, 775, 988, 306, 241, 587, 825, 583, 223, 995, 566, 1203, 695, 620,
        1100, 299, 537, 796, 1, 989, 1208, 328, 817, 1088, 791, 767, 165, 579, 487, 1067, 806,
        999, 1018, 1, 1177, 331, 634, 639, 1103, 1146, 1293, 233, 687, 439, 138, 1052, 658,
        713, 798, 1176, 685, 879, 333, 1062, 935, 458, 771, 839, 455, 755, 144, 1155, 1330,
        975, 440, 1160, 908, 126, 612, 16, 1137, 1051, 1242, 236, 616, 750, 871, 849, 345,
        1102, 306, 1277, 391, 333, 251, 891, 1223, 875, 88, 79, 1, 404, 427, 274, 904, 770,
        441, 959, 166, 146, 891, 284, 728, 1135, 915, 707, 105, 909, 232, 780, 98, 1232, 34,
        57, 1226, 66, 956, 272, 1183, 1194, 1014, 660, 357, 122, 755, 13, 472, 409, 853, 957,
        245, 26, 536, 527, 114, 796, 647, 376, 37, 127, 1100, 1138, 318, 268, 309, 873, 886,
        138, 786, 819, 557, 52, 118, 1045, 352, 708, 441, 638, 1041, 383, 399, 247, 1282, 127,
        243, 572, 473, 880, 166, 247, 365, 826, 182, 168, 633, 133, 298, 5, 91, 731, 308, 588,
        103, 1169, 429, 432, 310, 12, 1236, 1076, 521, 1249, 1343, 868, 1003
    ]

    /// r 2.4, opacity 0.38, static.
    static let midXY: [Int16] = [
        1022, 412, 1200, 807, 212, 895, 608, 376, 1167, 1125, 411, 357, 707, 1147, 1, 691,
        656, 1019, 390, 56, 510, 29, 372, 168, 208, 442, 774, 462, 33, 136, 35, 1082, 1152,
        1035, 853, 531, 500, 809, 53, 1142, 987, 82, 944, 1128, 579, 351, 625, 419, 1191, 833,
        210, 617, 46, 1353, 720, 981, 521, 425, 421, 473, 433, 1037, 147, 450, 886, 23, 1208,
        1027, 74, 449, 46, 1143, 331, 1068, 538, 775, 714, 831, 164, 118, 412, 1188, 491, 470,
        162, 895
    ]

    /// r 3.6, opacity 1, and the only ones that twinkle. The brief reads as
    /// though every star has its own loop; the artboard animates these seventeen
    /// and leaves the other 150 still, which is what keeps the field from
    /// shimmering like static.
    static let brightXY: [Int16] = [
        509, 1069, 531, 692, 994, 577, 704, 1133, 1037, 93, 245, 187, 134, 1296, 1013, 1049,
        788, 152, 253, 153, 319, 141, 987, 763, 452, 578, 613, 1082, 854, 1007, 526, 57, 12,
        1270
    ]

    /// Five durations against seven delays, walked in step, so no two of the
    /// seventeen bright stars ever share a phase.
    static let twinkleDurations: [Double] = [2.4, 2.78, 3.16, 3.54, 3.92]
    static let twinkleDelays: [Double] = [0, 0.26, 0.52, 0.78, 1.04, 1.3, 1.56]

    static var brightCount: Int { brightXY.count / 2 }
}

// MARK: Sky and globe

/// Starfield and globe, in one `Canvas`.
///
/// A `Canvas` rather than 167 `Circle` views: the field has to be one drawing
/// call per frame for the twinkle to be free, and the whole scene is redrawn off
/// a shared clock anyway. Everything is in artboard coordinates mapped through
/// `SplashArtboard`, so it crops exactly as the PNG did.
struct SplashSkyLayer: View {
    let frame: SplashFrame
    let theme: AppTheme

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let board = SplashArtboard(size: size)
            guard board.scale > 0 else { return }
            drawStars(into: &context, board: board)
            drawGlobe(into: &context, board: board)
        }
        // The sphere alone is 1800 artboard px across. Nothing here is text and
        // nothing here needs hit testing.
        .allowsHitTesting(false)
    }

    // MARK: Colours
    //
    // Tokens, not the design's literals - but the literals are what they resolve
    // to, and the two that cannot are called out.

    /// The design sets the stars in #FFFFFF on the dark ground and #8B94AA on the
    /// light one. Neither is a token. `text` IS the dark palette's white
    /// (#E9EDF7, indistinguishable at r 3.6), and #8B94AA is a mid grey that
    /// `textSecondary` reproduces exactly once its alpha is scaled - see below.
    private var starInk: Color {
        switch theme {
        case .dark: return theme.colors.text
        case .light: return theme.colors.textSecondary
        }
    }

    /// `textSecondary` on light is #5A6480, darker than the design's #8B94AA, so
    /// it lands on the same rendered grey at (0xF7 - 0x8B) / (0xF7 - 0x5A) = 0.688
    /// of the alpha. Derived from the exported PNG rather than guessed: the three
    /// star classes measure #E3E6ED / #CED2DD / #8B94AA on the light ground,
    /// which back out to 0.694, 0.674 and 0.675 of the declared 0.18 / 0.38 / 1.0.
    private var starInkScale: Double {
        theme == .light ? 0.688 : 1
    }

    /// The limb bloom.
    ///
    /// Dark takes `globeAtmosphere`, which is #4DA3FF at 40% - the design's value
    /// to the digit. Light cannot: `globeAtmosphere` is a sky blue there, and sky
    /// blue is the exact thing the brief threw out of the light palette. It takes
    /// `border` instead, which is #DCE2EF, again the design's value exactly.
    private var haloInk: Color {
        switch theme {
        case .dark: return theme.colors.globeAtmosphere
        case .light: return theme.colors.border
        }
    }

    /// The hairline on the limb itself. 0.22 dark, 0.10 light, both on `primary`.
    private var limbAlpha: Double {
        theme == .dark ? 0.22 : 0.10
    }

    // MARK: Drawing

    private func drawStars(into context: inout GraphicsContext, board: SplashArtboard) {
        context.opacity = frame.starsOpacity

        fill(SplashStars.dimXY, radius: 1.6, alpha: 0.18, into: &context, board: board)
        fill(SplashStars.midXY, radius: 2.4, alpha: 0.38, into: &context, board: board)

        for index in 0..<SplashStars.brightCount {
            let x = CGFloat(SplashStars.brightXY[index * 2])
            let y = CGFloat(SplashStars.brightXY[index * 2 + 1])
            context.fill(
                dot(at: board.point(x, y), radius: board.length(3.6)),
                with: .color(starInk.opacity(starInkScale * frame.twinkle(index)))
            )
        }

        context.opacity = 1
    }

    private func fill(
        _ interleaved: [Int16],
        radius: CGFloat,
        alpha: Double,
        into context: inout GraphicsContext,
        board: SplashArtboard
    ) {
        let colour = starInk.opacity(alpha * starInkScale)
        let r = board.length(radius)
        var path = Path()
        for index in stride(from: 0, to: interleaved.count, by: 2) {
            let centre = board.point(CGFloat(interleaved[index]), CGFloat(interleaved[index + 1]))
            path.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        }
        context.fill(path, with: .color(colour))
    }

    private func drawGlobe(into context: inout GraphicsContext, board: SplashArtboard) {
        // `translateY(320px)` in artboard space, eased and undone by `globeRise`.
        context.translateBy(x: 0, y: board.length(320) * (1 - frame.globeRise))

        let centre = board.point(645, 2140)
        let sphere = board.length(900)
        let bloom = board.length(1200)

        // Halo, as an ANNULUS rather than a disc.
        //
        // In the design it is a full disc that the opaque sphere covers, which is
        // the same picture at rest but not during the rise: for 1500ms the whole
        // group is semi-transparent, and a disc would show through the sphere as
        // a blue wash across its face. CSS gets this right for free because the
        // `<g>` composites as a group. Clipping the halo to the outside of the
        // limb gets the same result without a transparency layer.
        var halo = Path(ellipseIn: CGRect(
            x: centre.x - bloom, y: centre.y - bloom, width: bloom * 2, height: bloom * 2))
        halo.addPath(Path(ellipseIn: CGRect(
            x: centre.x - sphere, y: centre.y - sphere, width: sphere * 2, height: sphere * 2)))

        context.opacity = frame.globeOpacity * frame.haloOpacity
        context.fill(
            halo,
            with: .radialGradient(
                Gradient(stops: haloStops), center: centre, startRadius: 0, endRadius: bloom),
            style: FillStyle(eoFill: true)
        )

        let sphereRect = CGRect(
            x: centre.x - sphere, y: centre.y - sphere, width: sphere * 2, height: sphere * 2)

        context.opacity = frame.globeOpacity * frame.sphereOpacity
        context.fill(Path(ellipseIn: sphereRect), with: .color(theme.colors.globeBackground))

        context.opacity = frame.globeOpacity
        context.stroke(
            Path(ellipseIn: sphereRect),
            with: .color(theme.colors.primary.opacity(limbAlpha)),
            lineWidth: board.length(3)
        )

        context.opacity = 1
    }

    private func dot(at centre: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }

    /// The design blurs a disc of r 970 with a 60px Gaussian. Sampling that
    /// blur's own profile - a normal CDF of (970 - d) / 60 - reproduces it
    /// analytically, which costs one gradient instead of a full-screen blur pass.
    ///
    /// Locations are fractions of an outer radius of 1200 artboard px, where the
    /// profile has fallen below 1/1000. Checked against the exported PNG at
    /// d = 918, 938, 958, 978, 998, 1018, 1038 and 1058: within one 8-bit step
    /// of the measured alpha at every one.
    private var haloStops: [Gradient.Stop] {
        let profile: [(CGFloat, Double)] = [
            (0.0000, 1.0),
            (0.7500, 0.878),   // d =  900, the limb
            (0.7708, 0.773),   // d =  925
            (0.7917, 0.631),   // d =  950
            (0.8083, 0.500),   // d =  970, the disc's own edge
            (0.8250, 0.369),   // d =  990
            (0.8458, 0.227),   // d = 1015
            (0.8667, 0.122),   // d = 1040
            (0.8917, 0.048),   // d = 1070
            (0.9167, 0.015),   // d = 1100
            (0.9500, 0.002),   // d = 1140
            (1.0000, 0.0)
        ]
        return profile.map { Gradient.Stop(color: haloInk.opacity($0.1), location: $0.0) }
    }
}

// MARK: The mark

/// The flight path over the wordmark. `M24 136 Q310 -70 596 136`, from the
/// artboard, in a 620 x 150 box.
///
/// It is drawn as one path so `.trim(from:to:)` can walk it end to end. The
/// design's `stroke-dashoffset: 1 -> 0` over a path declared `pathLength="1"`
/// with `stroke-dasharray="1"` is the same thing: the visible run is 0...(1-offset),
/// growing from the departure end.
struct SplashFlightArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }
        let u = rect.width / 620
        path.move(to: CGPoint(x: rect.minX + 24 * u, y: rect.minY + 136 * u))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 596 * u, y: rect.minY + 136 * u),
            control: CGPoint(x: rect.minX + 310 * u, y: rect.minY - 70 * u)
        )
        return path
    }
}

/// SkyLine, set in the app's own face.
///
/// `.appFont(.titleLarge)` is 34pt; the artboard sets this at 128 artboard px.
/// The gap between them is closed with a constant `scale`, NOT by asking for a
/// bigger font, so Dynamic Type still moves the type - the scale multiplies
/// whatever size the token resolved to. `maxWidth` is pre-divided by that scale
/// by the caller, which is what lets `.appFont`'s minimum scale factor still do
/// its job: monospaced type cannot reflow inside a word, and "SkyLine" is one
/// seven-character word.
struct SplashWordmark: View {
    let theme: AppTheme
    /// Letter-spacing in em, animated 0.26 -> -0.01.
    let trackingEm: Double
    /// The point size `.appFont(.titleLarge)` actually resolved to.
    let typeSize: CGFloat
    let scale: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        // Interpolated rather than concatenated with `+`, which iOS 26 deprecated.
        Text("\(Text("Sky").foregroundStyle(theme.colors.text))\(Text("Line").foregroundStyle(theme.colors.primary))")
            .tracking(CGFloat(trackingEm) * typeSize)
            .appFont(.titleLarge, lineLimit: .exactly(1))
            .frame(maxWidth: maxWidth)
            .scaleEffect(scale)
    }
}

/// The arc, its two dots and the wordmark - one column, one animation.
///
/// `sl-rise` sits on the column, not on the type, so the arc lifts and fades with
/// the wordmark and only the draw-on is its own. Keeping that grouping matters:
/// the dots are positioned against the arc box, and the arc box against the
/// wordmark's rendered size, so the departure dot stays over the S and the
/// arrival dot over the e at every Dynamic Type size.
struct SplashMark: View {
    let frame: SplashFrame
    let theme: AppTheme
    let board: SplashArtboard
    /// Screen width, for the wordmark's shrink-to-fit budget.
    let available: CGFloat

    @ScaledMetric(relativeTo: .largeTitle)
    private var typeSize: CGFloat = AppTypography.Metrics.titleLarge

    var body: some View {
        let scale = board.length(SplashArtboard.wordmarkSize) / AppTypography.Metrics.titleLarge
        let rendered = typeSize * scale
        // One artboard px, in points, at whatever size the type resolved to.
        let u = rendered / SplashArtboard.wordmarkSize
        let centreX = board.point(645, 0).x
        // The column is pinned at artboard y 610 and grows downward. The arc box
        // is 150 tall with a -26 margin under it, so the wordmark's line box runs
        // 124...252 and its centre - which is what `.position` wants - is at 188.
        let top = board.point(0, 610).y

        ZStack {
            SplashFlightArc()
                .trim(from: 0, to: frame.arcProgress)
                .stroke(
                    theme.colors.primary,
                    style: StrokeStyle(lineWidth: 7 * u, lineCap: .round)
                )
                .frame(width: 620 * u, height: 150 * u)
                // `.trim(to: 0)` with a round cap can still leave a bead at the
                // start. Nothing is drawn before 900ms, so nothing should show.
                .opacity(frame.arcProgress > 0 ? 1 : 0)
                .overlay(alignment: .topLeading) {
                    // Departure, over the S, in ink - the same ink as "Sky".
                    Circle()
                        .fill(theme.colors.text)
                        .frame(width: 20 * u, height: 20 * u)
                        .offset(x: 14 * u, y: 126 * u)
                        .opacity(frame.departureOpacity)
                }
                .overlay(alignment: .topLeading) {
                    // Arrival, over the e, in the accent - the same accent as
                    // "Line". It lands at 2050ms, as the arc reaches it.
                    Circle()
                        .fill(theme.colors.primary)
                        .frame(width: 20 * u, height: 20 * u)
                        .offset(x: 586 * u, y: 126 * u)
                        .opacity(frame.arrivalOpacity)
                }
                .position(x: centreX, y: top + 75 * u)

            SplashWordmark(
                theme: theme,
                trackingEm: frame.trackingEm,
                typeSize: typeSize,
                scale: scale,
                maxWidth: max(available - AppSpacing.lg * 2, 1) / max(scale, 0.0001)
            )
            .position(x: centreX, y: top + 188 * u)
        }
        .offset(y: 14 * u * (1 - frame.markRise))
        .opacity(frame.markOpacity)
        .allowsHitTesting(false)
    }
}

// MARK: Composition

/// One instant of the whole splash.
struct SplashScene: View {
    let frame: SplashFrame
    let theme: AppTheme

    var body: some View {
        GeometryReader { proxy in
            let board = SplashArtboard(size: proxy.size)
            ZStack {
                SplashSkyLayer(frame: frame, theme: theme)
                SplashMark(
                    frame: frame,
                    theme: theme,
                    board: board,
                    available: proxy.size.width
                )
                // Held in step with `.appFont(.titleLarge)`, which caps itself at
                // accessibility3. `@ScaledMetric` has no such ceiling, and if the
                // two disagreed the arc would drift off the glyphs it points at.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
        }
    }
}

/// The splash, running.
struct SplashStage: View {
    let theme: AppTheme
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            // The ground does not animate. In the design it is a plain
            // `background` on the artboard and only the star group fades, which
            // is also what stops the first frame - and this view can be on
            // screen for a single frame - from being a flash of nothing.
            theme.colors.background

            if reduceMotion {
                SplashScene(frame: .resting, theme: theme)
            } else {
                // 60Hz, not the display's 120: the second time this view is up it
                // is sitting over a WebKit globe that is still booting, and the
                // splash has no business competing with it for the frame budget.
                //
                // Fully qualified. `TripDetailView` declares its own `TimelineView`
                // - a trip's day-by-day list - and an unqualified name resolves to
                // that one, module types shadowing SwiftUI's.
                SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                    SplashScene(
                        frame: SplashFrame(elapsed: SplashClock.elapsed(at: context.date)),
                        theme: theme
                    )
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("SkyLine"))
    }
}

/// Shown while authentication resolves, and again over the booting globe.
struct AppLoadingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SplashStage(theme: themeManager.currentTheme, reduceMotion: reduceMotion)
            .onAppear { SplashClock.splashAppeared() }
            .onDisappear { SplashClock.splashDisappeared() }
    }
}


// MARK: - Previews
//
// `SplashStage` rather than `AppLoadingView` so the theme is stated outright.
// `AppLoadingView` reads it from `ThemeManager`, which restores whatever the
// user last chose, so a "light" preview built that way would render dark.
#Preview("Splash - Light Mode") {
    SplashStage(theme: .light, reduceMotion: false)
        .preferredColorScheme(.light)
}

#Preview("Splash - Dark Mode") {
    SplashStage(theme: .dark, reduceMotion: false)
        .preferredColorScheme(.dark)
}

#Preview("Splash - Reduce Motion") {
    SplashStage(theme: .dark, reduceMotion: true)
        .preferredColorScheme(.dark)
}

#Preview("Splash - first frame") {
    SplashScene(frame: SplashFrame(elapsed: 0), theme: .dark)
        .background(AppTheme.dark.colors.background)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
}
