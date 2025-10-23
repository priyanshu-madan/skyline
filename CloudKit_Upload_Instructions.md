# CloudKit Destination Images Upload Guide

## Method 1: Using the Admin Interface (Easiest)

1. **Add Admin Tab** to your app (temporarily):
   ```swift
   // Add to SkyLineBottomBarView.swift enum
   case admin = "Admin"
   
   // Add to tab cases:
   case .admin:
       DestinationImageUploadView()
   ```

2. **Use the Upload Interface**:
   - Select image from Photos
   - Enter airport code (e.g., "LAX")
   - Enter city name (e.g., "Los Angeles")
   - Optional: country name
   - Tap "Upload to CloudKit"

## Method 2: Batch Upload from Local Folder

1. **Prepare Images**:
   - Name files: `AIRPORT_CODE - City Name.jpg`
   - Examples: `LAX - Los Angeles.jpg`, `JFK - New York.jpg`
   - Put in Documents/DestinationImages/ folder

2. **Run Batch Upload**:
   ```swift
   // Add this to your app (temporarily)
   Task {
       await DestinationImageBatchUploader.shared.uploadImagesFromDocuments()
   }
   ```

## Method 3: CloudKit Dashboard (Production Recommended)

1. **Access CloudKit Console**:
   - Go to [CloudKit Console](https://icloud.developer.apple.com/dashboard)
   - Select your app container: `iCloud.com.skyline.flighttracker`

2. **Navigate to Public Database**:
   - Select "Public Database"
   - Go to "Records" section

3. **Create DestinationImage Records**:
   - Click "+" to create new record
   - Select "DestinationImage" record type
   - Fill in fields:
     - `airportCode`: "LAX" (String)
     - `cityName`: "Los Angeles" (String)
     - `countryName`: "United States" (String, optional)
     - `imageURL`: "" (String, optional)
     - `image`: Upload image file (Asset)

4. **Repeat for Each Destination**

## Method 4: Automated Download from Unsplash

1. **Use the Manifest Uploader**:
   ```swift
   // Add this to your app (temporarily)
   Task {
       await DestinationImageBatchUploader.shared.uploadFromManifest()
   }
   ```

2. **This will automatically**:
   - Download high-quality images from Unsplash
   - Upload them to CloudKit with proper metadata
   - Handle rate limiting

## Image Requirements

- **Format**: JPG, PNG, HEIC
- **Size**: Recommended 800x600 or 1200x900
- **Quality**: High resolution for crisp display
- **Content**: City skylines, landmarks, airport views

## Airport Codes to Prioritize

### US Major Hubs:
- LAX (Los Angeles), JFK (New York), SFO (San Francisco)
- ORD (Chicago), ATL (Atlanta), DFW (Dallas), MIA (Miami)
- SEA (Seattle), DEN (Denver), LAS (Las Vegas), BOS (Boston)

### International Hubs:
- LHR (London), CDG (Paris), FRA (Frankfurt), AMS (Amsterdam)
- NRT/HND (Tokyo), ICN (Seoul), SIN (Singapore), HKG (Hong Kong)
- SYD (Sydney), DXB (Dubai), DOH (Doha), IST (Istanbul)

## Testing

After uploading, test by:
1. Opening flight details for a flight with that destination
2. Image should appear in the Aircraft Information Card section
3. Check CloudKit Console to verify records were created

## Troubleshooting

- **Upload Fails**: Check CloudKit permissions and container ID
- **Images Don't Appear**: Verify airport code matches exactly
- **Slow Loading**: Images are cached after first load
- **Rate Limits**: Add delays between uploads (1-2 seconds)

## Production Notes

- Remove admin interface before App Store submission
- Use CloudKit Dashboard for ongoing image management
- Consider content moderation for user-uploaded images
- Monitor CloudKit usage and costs