# CloudKit Setup Instructions

## Xcode Project Configuration

To enable CloudKit sync in your SkyLine app, follow these steps:

### 1. Enable CloudKit Capability
1. Open your Xcode project
2. Select your app target in the Project Navigator
3. Go to the "Signing & Capabilities" tab
4. Click "+ Capability" and add "CloudKit"
5. Your Apple Developer Team will be automatically selected

### 2. CloudKit Container
1. In the CloudKit section, click "+" to add a container
2. Use the identifier: `iCloud.com.skyline.flighttracker`
3. Make sure "Use Core Data with CloudKit" is **unchecked** (we're using custom CloudKit integration)

### 3. CloudKit Schema
The app will automatically create the following record types in CloudKit:

#### Flight Record Type
- Fields: flightNumber (String), airline (String), status (String), etc.
- All flight data including departure/arrival airports and aircraft info

#### SearchHistory Record Type  
- Fields: query (String), order (Int)
- User's recent flight searches

### 4. Testing
- **Simulator**: CloudKit works in iOS Simulator when signed into iCloud
- **Device**: Must be signed into iCloud account in Settings
- **Multiple Devices**: Sign into the same iCloud account to test sync

### 5. Production Deployment
- Ensure your Apple Developer account has CloudKit enabled
- Deploy CloudKit schema to Production environment before App Store release
- Test thoroughly on multiple devices with different iCloud accounts

## Features Enabled

✅ **Automatic Sync**: Flights sync automatically when added/removed  
✅ **Conflict Resolution**: Server-side data takes precedence  
✅ **Offline Support**: App works offline, syncs when connection restored  
✅ **Background Sync**: Real-time updates via CloudKit subscriptions  
✅ **Cross-Device**: Same flights appear on all user's devices  
✅ **iCloud Integration**: Uses user's existing iCloud account  

## Privacy & Security

- All data stored in user's private CloudKit database
- No data shared between users
- Automatic encryption in transit and at rest
- Respects iCloud storage quotas
- Works with Apple's privacy initiatives