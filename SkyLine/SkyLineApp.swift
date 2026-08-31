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
                CloudKitService.shared.enableBackgroundSync()
                
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
struct AppLoadingView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Image("SplashScreen")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }
}

// MARK: - Previews
#Preview("Splash - Light Mode") {
    AppLoadingView()
        .environmentObject(ThemeManager())
        .preferredColorScheme(.light)
}

#Preview("Splash - Dark Mode") {
    AppLoadingView()
        .environmentObject(ThemeManager())
        .preferredColorScheme(.dark)
}
