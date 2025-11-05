# SkyLine: How It Works

## Overview

**SkyLine** is a native iOS flight tracking application built with SwiftUI that allows users to search for flights, scan boarding passes using OCR, visualize flight paths on an interactive 3D globe, and sync their flight data across devices using iCloud. The app provides a complete flight management experience with Apple Sign In authentication and CloudKit synchronization.

---

## Architecture

### Technology Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Authentication**: Apple Sign In (AuthenticationServices)
- **Cloud Sync**: CloudKit (iCloud)
- **OCR**: Vision Framework
- **Networking**: URLSession
- **3D Visualization**: Globe.gl (WebKit WebView with JavaScript bridge)
- **State Management**: Combine framework with ObservableObject pattern
- **Local Storage**: UserDefaults (for flights, preferences, search history)

### Design Pattern

The app follows the **MVVM (Model-View-ViewModel)** architecture pattern:

- **Models**: Data structures (`Flight`, `Airport`, `Aircraft`, `User`, `Trip`)
- **Views**: SwiftUI views for UI presentation
- **ViewModels**: ObservableObject classes (`FlightStore`, `ThemeManager`, `TripStore`)
- **Services**: Business logic layer (`AuthenticationService`, `CloudKitService`, `FlightAPIService`, `BoardingPassScanner`)

---

## Core Components

### 1. Application Entry Point

**File**: `SkyLineApp.swift`

The main app entry point manages the overall application state and authentication flow:

```swift
@main
struct SkyLineApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var flightStore = FlightStore()
    @StateObject private var authService = AuthenticationService.shared

    var body: some Scene {
        // Routes between authentication states
        switch authService.authenticationState {
        case .authenticated:
            // Show main app
        case .authenticating:
            // Show loading screen
        case .unauthenticated, .error:
            // Show Apple Sign In screen
        }
    }
}
```

**Key Responsibilities**:
- Manages global state objects (theme, flights, authentication)
- Routes between authentication states
- Configures immersive UI appearance (navigation/tab bars)
- Enables CloudKit background sync
- Syncs trip data when app comes to foreground

### 2. Authentication System

**File**: `Services/AuthenticationService.swift`

Handles user authentication using Apple Sign In:

**Authentication Flow**:
1. User taps "Sign in with Apple" button
2. Apple presents authentication prompt (Face ID/Touch ID)
3. On success, receives Apple ID credential with user info
4. Creates `User` object and stores in UserDefaults
5. Sets authentication state to `.authenticated(user)`
6. App automatically shows main interface

**Persistence**:
- Checks for existing authentication on app launch
- Validates Apple ID credential state
- Automatically signs in if credential is still valid
- Users stay logged in between app sessions

**States**:
- `.unauthenticated` - No user logged in
- `.authenticating` - Checking existing credentials
- `.authenticated(User)` - User is logged in
- `.error(String)` - Authentication failed

### 3. Data Models

**File**: `Models/Flight.swift`

Core data structures:

**Flight Model**:
```swift
struct Flight: Codable, Identifiable {
    let id: String
    let flightNumber: String
    let airline: String?
    let departure: Airport
    let arrival: Airport
    let status: FlightStatus
    let aircraft: Aircraft?
    let currentPosition: FlightPosition?
    let progress: Double?
    let flightDate: String?
    let dataSource: DataSource
    let date: Date
}
```

**Airport Model**:
- Airport name, code, city
- Coordinates (latitude/longitude)
- Scheduled and actual times
- Terminal and gate information
- Delay information

**FlightStatus Enum**:
- `boarding`, `departed`, `inAir`, `landed`, `delayed`, `cancelled`

**DataSource Enum**:
- `opensky` - OpenSky Network API
- `aviationstack` - AviationStack API
- `combined` - Multiple sources
- `pkpass` - Apple Wallet boarding pass
- `manual` - User-entered or OCR scanned

### 4. Flight Management (FlightStore)

**File**: `ViewModels/FlightStore.swift`

The central data store for all flight-related operations:

**Published Properties**:
```swift
@Published var flights: [Flight] = []
@Published var selectedFlight: Flight?
@Published var searchHistory: [String] = []
@Published var isLoading: Bool = false
@Published var isSyncing: Bool = false
```

**Key Features**:
- **CRUD Operations**: Add, remove, update flights
- **Local Persistence**: Saves to UserDefaults automatically
- **CloudKit Sync**: Bidirectional sync with iCloud
- **Flight Sorting**: By status priority and flight number
- **Search History**: Tracks recent searches
- **Auto-save**: Debounced saving on changes

**How Flight Storage Works**:
1. Flights stored locally in UserDefaults as JSON
2. On app launch, flights loaded from UserDefaults
3. When authenticated, flights synced to CloudKit
4. Changes trigger auto-save (debounced 1 second)
5. CloudKit sync runs on add/remove/app foreground

### 5. CloudKit Synchronization

**File**: `Services/CloudKitService.swift`

Manages iCloud sync for cross-device data sharing:

**Record Types**:
- `Flight` - User's saved flights (private database)
- `SearchHistory` - Recent searches (private database)
- `DestinationImage` - Destination photos (private database)
- `Trip` - Travel journals (private database)
- `TripEntry` - Trip timeline entries (private database)
- `SharedAirportCoordinates` - Airport coordinates cache (private database)

**Sync Strategy**:
1. **Local-first**: All data stored locally first
2. **Async upload**: Data uploaded to CloudKit in background
3. **Conflict resolution**: Server wins (most recent CloudKit data)
4. **Offline support**: Works without internet, syncs when available
5. **Background sync**: CloudKit subscriptions for real-time updates

**How Sync Works**:
```
User adds flight → Save to UserDefaults → Upload to CloudKit
                                        ↓
Other device → CloudKit subscription → Download → Merge with local
```

### 6. Flight Search & OCR

**File**: `Services/FlightAPIService.swift` & `Services/BoardingPassScanner.swift`

**Flight Search**:
1. User enters flight number (e.g., "AA123")
2. API call to AviationStack or OpenSky Network
3. Flight data parsed and airport coordinates resolved
4. Results displayed in search results cards
5. User taps "Save" to add to their flights

**Boarding Pass OCR**:
1. User taps "Scan Boarding Pass"
2. PhotosPicker opens for image selection
3. Vision framework extracts text from image
4. Smart regex parsing extracts:
   - Flight number
   - Departure/arrival airports
   - Date and time
   - Passenger name
   - Gate and seat information
5. Confirmation view shows parsed data
6. User can edit before saving

**OCR Parsing Logic**:
```swift
// Extract flight number
"Flight: UA546" or "UA 546" → Captures "UA546"

// Extract airport codes
"SFO → ORD" or "SFO-ORD" → Departure: SFO, Arrival: ORD

// Extract date
"24 AUG" or "08/24/2025" → Parsed to Date object

// Extract gate
"Gate: B12" or "Gate B12" → "B12"
```

### 7. 3D Globe Visualization

**File**: `Views/WebViewGlobeView.swift` & `globe.html`

The app uses **Globe.gl** JavaScript library embedded in a WKWebView for 3D globe visualization.

**Architecture**:
```
SwiftUI View → WKWebView → globe.html → Globe.gl library
     ↓                                        ↓
JavaScript Bridge ← ← ← ← ← ← ← ← Flight data
```

**Features**:
- Interactive 3D Earth with hexagonal land masses
- Flight paths displayed as arcs between airports
- Airport labels with city names
- Flight selection and focusing
- Smooth animations and rotations
- Blue airport labels, green visited city markers

**Swift ↔ JavaScript Communication**:

**Swift to JavaScript**:
```swift
// Focus on a flight
webView.evaluateJavaScript("""
    window.focusOnFlightById('\(flightId)', '\(flightNumber)');
""")
```

**JavaScript to Swift**:
```javascript
// Send message back to Swift
window.webkit.messageHandlers.reactNativeWebView.postMessage({
    type: 'FLIGHT_FOCUS_SUCCESS',
    flightNumber: 'UA546'
});
```

**Globe Data Update Flow**:
1. FlightStore flights change
2. Swift converts flights to JSON
3. JavaScript `updateFlightData()` called with JSON
4. Globe.gl arcs data updated
5. Globe re-renders with new flight paths

### 8. User Interface

**File**: `ContentView.swift`

The main UI is a **bottom sheet over a globe background**:

```
┌─────────────────────────────┐
│                             │
│    3D Globe (WebView)       │
│                             │
│                             │
├─────────────────────────────┤
│ ┌───┬───┬───┬───┬───┐      │ ← Bottom Sheet
│ │ 🌍 │ 🔍 │ ✈️ │ 👤 │      │   (Draggable)
│ └───┴───┴───┴───┴───┘      │
│   [Tab Content]             │
└─────────────────────────────┘
```

**Bottom Sheet Detents**:
- `.height(80)` - Collapsed (only tab bar visible)
- `.fraction(0.2)` - Slightly expanded
- `.fraction(0.3)` - Flight details view
- `.fraction(0.6)` - Search/list view
- `.large` - Full screen

**Four Tabs**:

1. **🌍 Globe**:
   - Shows 3D globe with flight paths
   - Displays visited cities as green markers
   - Interactive flight selection

2. **🔍 Search**:
   - Manual flight number search
   - OCR boarding pass scanning
   - Search results with flight cards
   - Save flights to collection

3. **✈️ Flights**:
   - List of saved flights
   - Swipe-to-delete gestures
   - Flight details in expandable sheet
   - Pull-to-refresh for updates

4. **👤 Profile**:
   - User information (Apple ID)
   - Flight statistics (total flights, cities, countries)
   - iCloud sync status and controls
   - Theme switching (light/dark)
   - Data management (clear all)
   - Sign out

### 9. Travel Journal System

**Files**: `Models/Trip.swift`, `Services/TripStore.swift`, `Views/Trips/`

SkyLine includes a comprehensive travel journal feature:

**Trip Model**:
- Trip name and destination
- Start and end dates
- Cover image
- Timeline entries (diary-style entries with photos)

**Trip Entries**:
- Date and location
- Photos from photo library
- Text notes and memories
- Linked to specific trips

**CloudKit Sync**:
- Trips synced across devices
- Photos uploaded to CloudKit as CKAsset
- Offline-first with background sync
- Conflict resolution (server wins)

**How It Works**:
1. User creates trip (e.g., "Tokyo Adventure")
2. Adds timeline entries with photos and notes
3. Data saved locally and uploaded to CloudKit
4. Other devices receive trip via CloudKit subscription
5. Photos downloaded on-demand for viewing

### 10. Airport Coordinate System

**Files**: `Services/AirportService.swift`, `Services/SharedAirportService.swift`

The app maintains airport coordinates for globe visualization:

**Local Database**:
- 50+ major airports hardcoded in `AirportService`
- Instant coordinate lookup for common airports

**Dynamic Fetching**:
- Unknown airports fetched from API Ninjas
- Coordinates cached in CloudKit shared database
- Shared across all users (reduces API calls)

**Lookup Flow**:
```
Need coordinates for "SIN"
    ↓
1. Check local database → Found? Use it
                              ↓ Not found
2. Check CloudKit cache → Found? Use it
                              ↓ Not found
3. Fetch from API Ninjas → Save to CloudKit for all users
                              ↓
4. Use coordinates in flight data
```

---

## Data Flow Examples

### Example 1: Adding a Flight via OCR

```
1. User: Tap "Scan Boarding Pass"
   ↓
2. PhotosPicker: Select image from library
   ↓
3. BoardingPassScanner: Vision framework extracts text
   ↓
4. Parser: Regex extracts flight number, airports, date, gate
   ↓
5. UI: Confirmation view shows parsed data (editable)
   ↓
6. User: Tap "Add Flight"
   ↓
7. FlightStore: Create Flight object with parsed data
   ↓
8. AirportService: Resolve airport coordinates
   ↓
9. FlightStore: Add to flights array
   ↓
10. Auto-save: Save to UserDefaults (debounced)
    ↓
11. CloudKitService: Upload to iCloud
    ↓
12. WebView: Update globe with new flight path
    ↓
13. UI: Show success, display flight in Flights tab
```

### Example 2: Cross-Device Sync

```
Device A: User adds flight "UA546"
    ↓
FlightStore: Save locally, trigger CloudKit upload
    ↓
CloudKitService: Create CKRecord, upload to iCloud
    ↓
iCloud: Store record, send push notification to Device B
    ↓
Device B: CloudKit subscription receives notification
    ↓
CloudKitService: Fetch new flight record
    ↓
FlightStore: Merge with local flights (avoid duplicates)
    ↓
UI: Automatically updates to show new flight
    ↓
Globe: New flight path appears on 3D globe
```

### Example 3: App Launch Authentication

```
1. App launches → SkyLineApp.body executes
   ↓
2. AuthenticationService.init() called
   ↓
3. State set to .authenticating (shows loading screen)
   ↓
4. checkExistingAuthentication() reads UserDefaults
   ↓
5. Found cached User object?
   ├─ Yes → Validate Apple ID credential state
   │         ├─ Valid → Set state to .authenticated(user)
   │         └─ Invalid → Set state to .unauthenticated
   └─ No → Set state to .unauthenticated
       ↓
6. State .authenticated?
   ├─ Yes → Show ContentView (main app)
   └─ No → Show AuthenticationView (sign in screen)
       ↓
7. If authenticated:
   - Load flights from UserDefaults
   - Sync with CloudKit
   - Load globe with flight data
   - Enable background sync subscriptions
```

---

## Key Features Explained

### 1. Offline Support

The app works completely offline:
- All data stored locally in UserDefaults
- CloudKit sync happens in background when online
- No internet required for viewing saved flights
- OCR works offline (Vision framework is on-device)
- Globe visualization works offline (embedded HTML)

### 2. Real-time Sync

CloudKit subscriptions enable real-time updates:
```swift
// Enable background sync
CloudKitService.shared.enableBackgroundSync()

// Subscribe to database changes
database.add(subscription)

// Handle notifications
func handleNotification(_ notification: CKNotification) {
    syncFlights()
}
```

### 3. Theme System

**File**: `Models/Theme.swift`

Two themes: light and dark
- Color schemes for UI elements
- Automatically follows system theme or manual override
- Smooth transitions between themes
- Persisted in UserDefaults

### 4. Haptic Feedback

Tactile feedback throughout the app:
- Button taps (light impact)
- Flight added (success notification)
- Flight removed (warning notification)
- Swipe gestures (selection feedback)

### 5. Smart Flight Sorting

Flights sorted by priority:
1. Boarding (most urgent)
2. Departed
3. In Air
4. Delayed
5. Landed
6. Cancelled

Within same status, sorted alphabetically by flight number.

---

## API Integration

### AviationStack API
- Flight search by flight number
- Real-time flight status
- Departure/arrival times
- Gate and terminal info
- Aircraft details

### OpenSky Network API
- Live flight positions
- Aircraft telemetry (altitude, speed, heading)
- Real-time tracking data

### API Ninjas Airport API
- Airport coordinate lookup
- Dynamic airport data
- Fallback for unknown airports

---

## Security & Privacy

### Authentication
- Apple Sign In (industry-standard OAuth)
- No passwords stored locally
- Face ID/Touch ID biometric auth
- Credential validation on each launch

### Data Storage
- Local data in sandboxed UserDefaults
- CloudKit uses Apple's iCloud encryption
- Private database (only user can access)
- No third-party analytics or tracking

### Permissions
- Photo library access (for OCR)
- iCloud access (for sync)
- Network access (for APIs)
- All permissions requested with clear descriptions

---

## Performance Optimizations

### 1. Auto-save Debouncing
Prevents excessive writes:
```swift
// Save only after 1 second of inactivity
.debounce(for: .seconds(1), scheduler: RunLoop.main)
```

### 2. Lazy Loading
- Flights loaded from UserDefaults only once on init
- Images loaded on-demand in trip entries
- CloudKit queries paginated (limited results)

### 3. Coordinate Caching
- Airport coordinates cached locally and in CloudKit
- Reduces API calls by 95%
- Shared cache benefits all users

### 4. WebView Optimization
- Single WebView instance (not recreated)
- JavaScript communication minimized
- Globe data updates batched

---

## Error Handling

### Network Errors
- Graceful fallback to cached data
- User-friendly error messages
- Retry mechanisms for API failures

### CloudKit Errors
- Offline detection
- Conflict resolution (server wins)
- Automatic retry with exponential backoff

### OCR Errors
- Clear feedback when text extraction fails
- Manual editing always available
- Helpful tips for better scanning

---

## Future Enhancements

Based on the TODO.md file, potential improvements include:

1. **Real-time flight tracking** - Live aircraft positions on globe
2. **Smart notifications** - Flight delay/gate change alerts
3. **Apple Watch app** - Quick flight status on wrist
4. **Widgets** - Home screen widgets for next flight
5. **Shortcuts integration** - Siri commands for flight lookup
6. **Advanced analytics** - Travel insights and statistics
7. **Social features** - Share flights with friends/family

---

## Development Notes

### Project Structure
```
SkyLine/
├── Models/               # Data structures
├── Views/                # SwiftUI views
│   ├── Components/       # Reusable UI components
│   ├── Trips/            # Travel journal views
│   └── Admin/            # Admin tools
├── ViewModels/           # State management
├── Services/             # Business logic
├── Utils/                # Utilities and helpers
├── Extensions/           # Swift extensions
├── Archive/              # Legacy/backup code
└── Assets.xcassets/      # Images and colors
```

### Dependencies (Swift Package Manager)
- No external dependencies!
- All features built with native Apple frameworks
- Globe.gl embedded as local HTML/JS file

### iOS Target
- Minimum: iOS 15.0
- Optimized for: iOS 16.0+
- Compatible with: iPhone and iPad

---

## Conclusion

SkyLine is a full-featured flight tracking app that demonstrates modern iOS development best practices:

- **SwiftUI** for declarative UI
- **Combine** for reactive programming
- **CloudKit** for seamless sync
- **Vision** for OCR capabilities
- **MVVM** architecture for maintainability
- **Local-first** design for reliability

The app provides a delightful user experience with smooth animations, offline support, cross-device sync, and an immersive 3D globe visualization that makes flight tracking fun and engaging.

---

*Last Updated: November 5, 2025*
