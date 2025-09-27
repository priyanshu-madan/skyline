# Archive Folder

This folder contains files that are not currently being used in the active SkyLine app but are kept for reference or potential future use.

## Current Active Structure (DO NOT EDIT THESE FILES IN ARCHIVE)

### Main App Files (Active):
- `SkyLineApp.swift` - Main app entry point
- `ContentView.swift` - Main view with sheet presentation
- `SkyLineBottomBarView.swift` - Tab bar with 4 tabs (Globe, Flights, Search, Profile)
- `BottomSheetContentView.swift` - Add flight functionality
- `WebViewGlobeView.swift` - Globe display using web view

### Models & Services (Active):
- `Models/Flight.swift`, `Models/User.swift`, `Models/Theme.swift`
- `ViewModels/FlightStore.swift`
- `Services/` - All service files are active

### Components (Active):
- `Views/Components/` - All component files in this folder
- `Views/AuthenticationView.swift`
- `Views/SharedComponents.swift`

## Archived Files (In this folder):

### Alternative Views:
- `BottomSheetView.swift` - Original bottom sheet (replaced by tab structure)
- `FlightsView.swift` - Standalone flights view (now in SkyLineBottomBarView)
- `SearchView.swift` - Standalone search view (now in SkyLineBottomBarView) 
- `ProfileView.swift` - Standalone profile view (now in SkyLineBottomBarView)

### Alternative Globe Views:
- `NativeGlobeView.swift` - Native Swift globe implementation
- `Globe3DView.swift` - 3D globe view
- `GlobeView.swift` - Alternative globe view

### Backup & Alternative Apps:
- `SkyLineApp_backup.swift` - Backup of main app
- `MinimalApp.swift` - Minimal app implementation
- `SimpleContentView.swift` - Simple content view

### Duplicate Components:
- `SupportingViews.swift` - Duplicate (active one in Views/Components/)
- `FlightCardView.swift` - Duplicate (active one in Views/Components/)
- `GeistMono.zip` - Duplicate font file

## Note:
These files are archived to keep the active codebase clean and avoid accidental edits to unused code. They can be restored if needed but should not be modified while in archive.