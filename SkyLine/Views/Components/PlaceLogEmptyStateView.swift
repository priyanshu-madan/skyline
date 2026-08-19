//
//  PlaceLogEmptyStateView.swift
//  SkyLine
//
//  Empty states for the place log. Deliberately hand-rolled rather than
//  `ContentUnavailableView`, which forces the system font and would break the
//  app's monospaced identity.
//

import SwiftUI

// MARK: - Empty State Kind
enum PlaceLogEmptyState {
    /// Clustering ran and found nothing — the common case, and not the user's fault.
    case noPlacesDetected(destination: String?)
    /// Photo library access was never granted or was limited to a few pictures.
    case photoAccessDenied
    /// Photo library access is limited; more photos would find more places.
    case photoAccessLimited
    /// The user has no trips yet, so there is nothing to cluster.
    case noTrips
    /// Every detected place already has a verdict.
    case allPlacesJudged
    /// Clustering failed outright.
    case clusteringFailed(message: String?)

    var systemImage: String {
        switch self {
        case .noPlacesDetected: return "mappin.and.ellipse"
        case .photoAccessDenied: return "photo.badge.exclamationmark"
        case .photoAccessLimited: return "photo.stack"
        case .noTrips: return "suitcase"
        case .allPlacesJudged: return "checkmark.seal.fill"
        case .clusteringFailed: return "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .noPlacesDetected: return "No places found"
        case .photoAccessDenied: return "Photos are off"
        case .photoAccessLimited: return "Only some photos"
        case .noTrips: return "No trips yet"
        case .allPlacesJudged: return "All caught up"
        case .clusteringFailed: return "Could not read photos"
        }
    }

    var message: String {
        switch self {
        case .noPlacesDetected(let destination):
            if let destination, !destination.isEmpty {
                return "We could not find photos with a location in \(destination) for these dates. Add places by hand, or widen the trip dates."
            }
            return "We could not find photos with a location for these dates. Add places by hand, or widen the trip dates."
        case .photoAccessDenied:
            return "SkyLine builds your place log from where your photos were taken. Nothing leaves your device."
        case .photoAccessLimited:
            return "SkyLine can only see the photos you picked. Allowing full access finds more of the places you actually went."
        case .noTrips:
            return "Add a trip and SkyLine will turn its photos into the places you spent time in."
        case .allPlacesJudged:
            return "Every place on this trip has a verdict. Your map and your guide are up to date."
        case .clusteringFailed(let message):
            return message ?? "Something went wrong reading your photo library. Try again in a moment."
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .noPlacesDetected: return "Add a place"
        case .photoAccessDenied: return "Open Settings"
        case .photoAccessLimited: return "Manage access"
        case .noTrips: return "Add a trip"
        case .allPlacesJudged: return "See your guide"
        case .clusteringFailed: return "Try again"
        }
    }

    var secondaryActionTitle: String? {
        switch self {
        case .noPlacesDetected: return "Change dates"
        case .photoAccessLimited: return "Continue anyway"
        default: return nil
        }
    }

    /// `allPlacesJudged` is a success, not a dead end — tint it accordingly.
    func accentColor(for theme: AppTheme) -> Color {
        switch self {
        case .allPlacesJudged: return theme.colors.verdictWorthIt
        case .clusteringFailed, .photoAccessDenied: return theme.colors.verdictSkip
        default: return theme.colors.textSecondary
        }
    }
}

// MARK: - Empty State View
struct PlaceLogEmptyStateView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let state: PlaceLogEmptyState
    var onPrimaryAction: (() -> Void)? = nil
    var onSecondaryAction: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 44
    @ScaledMetric(relativeTo: .largeTitle) private var glyphWell: CGFloat = 88

    var body: some View {
        let theme = themeManager.currentTheme
        let accent = state.accentColor(for: theme)

        VStack(spacing: AppSpacing.md) {
            Image(systemName: state.systemImage)
                .font(.system(size: glyphSize, weight: .regular, design: .monospaced))
                .foregroundStyle(accent)
                .symbolRenderingMode(.hierarchical)
                .frame(width: glyphWell, height: glyphWell)
                .skylineGlass(.card, in: Circle(), tint: accent.opacity(0.22), theme: theme)

            VStack(spacing: AppSpacing.sm) {
                Text(state.title)
                    .appFont(.headline)
                    .foregroundStyle(theme.colors.text)
                    .multilineTextAlignment(.center)

                Text(state.message)
                    .appFont(.bodySmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if state.primaryActionTitle != nil || state.secondaryActionTitle != nil {
                SkyLineGlassPanel(spacing: AppSpacing.sm) {
                    VStack(spacing: AppSpacing.sm) {
                        if let title = state.primaryActionTitle, let onPrimaryAction {
                            Button {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                                onPrimaryAction()
                            } label: {
                                Text(title)
                                    .appFont(.bodyBold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, AppSpacing.xs)
                            }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                            .tint(theme.colors.primary)
                        }

                        if let title = state.secondaryActionTitle, let onSecondaryAction {
                            Button {
                                onSecondaryAction()
                            } label: {
                                Text(title)
                                    .appFont(.bodySmall)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, AppSpacing.xs)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .frame(maxWidth: 320)
                }
                .padding(.top, AppSpacing.xs)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews
#Preview("No places") {
    PlaceLogEmptyStateView(
        state: .noPlacesDetected(destination: "Tokyo"),
        onPrimaryAction: {},
        onSecondaryAction: {}
    )
    .environmentObject(ThemeManager())
}

#Preview("All judged") {
    PlaceLogEmptyStateView(state: .allPlacesJudged, onPrimaryAction: {})
        .environmentObject(ThemeManager())
}
