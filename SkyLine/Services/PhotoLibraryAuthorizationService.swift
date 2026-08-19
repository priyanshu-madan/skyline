//
//  PhotoLibraryAuthorizationService.swift
//  SkyLine
//
//  PHPhotoLibrary read authorization, including the limited-access case.
//

import Foundation
import Photos
import PhotosUI
import UIKit
import Combine

// MARK: - Access State

/// Collapses PHAuthorizationStatus into the four cases the UI actually branches on.
enum PhotoLibraryAccess: String, Sendable {
    case notDetermined
    case full
    case limited
    case denied      // includes .restricted — same dead end for the user
}

@MainActor
final class PhotoLibraryAuthorizationService: ObservableObject {

    // MARK: - Properties

    static let shared = PhotoLibraryAuthorizationService()

    @Published private(set) var access: PhotoLibraryAccess = .notDetermined
    @Published var error: String?

    private init() {
        access = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    // MARK: - Authorization

    /// Requests read access.
    ///
    /// `.readWrite` rather than `.addOnly`: we must READ the library to cluster
    /// it. Verified against the iOS 26.0 SDK header — `+authorizationStatus`
    /// and `+requestAuthorization:` (no access level) are both deprecated in
    /// favour of the `ForAccessLevel:` variants, and the level-taking request
    /// carries NS_SWIFT_ASYNC(2), so the async form below is the imported one.
    ///
    /// iOS 26 note: there is no separate "read-only" access level. `.readWrite`
    /// is the only level that grants reads, and it is what the system prompt
    /// describes to the user using NSPhotoLibraryUsageDescription.
    @discardableResult
    func requestAccess() async -> PhotoLibraryAccess {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != .notDetermined {
            access = Self.map(current)
            print("📱 PhotoAuth: Already resolved → \(access.rawValue)")
            return access
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = Self.map(status)

        switch access {
        case .full:    print("✅ PhotoAuth: Full library access granted")
        case .limited: print("⚠️ PhotoAuth: Limited library access granted")
        case .denied:  print("❌ PhotoAuth: Library access denied")
        case .notDetermined: print("⚠️ PhotoAuth: Still undetermined after request")
        }
        return access
    }

    /// Re-reads the status without prompting. Call from `scenePhase == .active`
    /// so a change made in Settings is picked up when the user comes back.
    func refresh() {
        let mapped = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        if mapped != access {
            print("🔄 PhotoAuth: Access changed \(access.rawValue) → \(mapped.rawValue)")
            access = mapped
        }
    }

    // MARK: - Limited Access

    /// Presents the system picker so a limited-access user can widen the
    /// selection for this trip.
    ///
    /// Requires `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = YES` in
    /// Info.plist, otherwise iOS shows its own nagging alert once per launch
    /// AND this picker, which reads as a bug. With the key set we own the
    /// timing completely: the picker only appears when the user taps
    /// "Choose more photos" on the degraded-results banner.
    func presentLimitedPicker() {
        guard access == .limited else { return }
        guard let controller = Self.topViewController() else {
            print("❌ PhotoAuth: No view controller to present limited picker from")
            return
        }
        print("🎯 PhotoAuth: Presenting limited library picker")
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    /// Deep-links to this app's Settings page for the `.denied` dead end.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Helpers

    private static func map(_ status: PHAuthorizationStatus) -> PhotoLibraryAccess {
        switch status {
        case .notDetermined:            return .notDetermined
        case .authorized:               return .full
        case .limited:                  return .limited
        case .denied, .restricted:      return .denied
        @unknown default:               return .denied
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
