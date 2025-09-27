# Privacy Permissions Required

## Photo Library Access

Add the following to your Info.plist file in Xcode:

### Key: `NSPhotoLibraryUsageDescription`
### Value: `SkyLine needs access to your photo library to scan boarding pass screenshots and extract flight details automatically.`

## How to Add in Xcode:

1. Open your project in Xcode
2. Select the SkyLine target
3. Go to the "Info" tab
4. Click the "+" button to add a new key
5. Type: `NSPhotoLibraryUsageDescription`
6. Set value to: `SkyLine needs access to your photo library to scan boarding pass screenshots and extract flight details automatically.`

This permission is required for the PhotosPicker to work when scanning boarding pass screenshots.