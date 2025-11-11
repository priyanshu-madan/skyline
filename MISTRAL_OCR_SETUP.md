# Mistral OCR Integration Guide

SkyLine now features advanced AI-powered OCR using Mistral AI's state-of-the-art document understanding technology, achieving ~94.9% accuracy compared to traditional OCR solutions.

## Features

✅ **Enhanced Accuracy**: Mistral OCR achieves ~94.9% accuracy vs 83.4% for Google Document AI  
✅ **Smart Document Understanding**: Comprehends structure, context, and complex layouts  
✅ **Multilingual Support**: Recognizes thousands of languages and scripts  
✅ **Automatic Fallback**: Uses Vision framework when Mistral API isn't available  
✅ **Structured Output**: Returns organized data in markdown format  

## Setup Instructions

### 1. Get Mistral API Key

1. Visit [Mistral AI Platform](https://console.mistral.ai/)
2. Create an account or sign in
3. Navigate to API Keys section
4. Create a new API key
5. Copy the key (starts with `mistral_...`)

### 2. Configure API Key

**Option A: Environment Variable (Recommended for development)**
```bash
export MISTRAL_API_KEY="your_actual_mistral_api_key_here"
```

**Option B: Info.plist (For app distribution)**
1. Open `SkyLine/Info.plist`
2. Replace `YOUR_MISTRAL_API_KEY_HERE` with your actual key:
```xml
<key>MISTRAL_API_KEY</key>
<string>your_actual_mistral_api_key_here</string>
```

### 3. Verification

When you run the app, check the console logs:
- ✅ `Using Mistral API key from environment/Info.plist` = Success
- ⚠️ `MISTRAL_API_KEY not found` = Falling back to Vision framework

## How It Works

### Enhanced OCR Pipeline

1. **Image Processing**: Optimizes image for OCR processing
2. **Mistral AI Analysis**: Extracts text with context understanding
3. **Smart Parsing**: Uses AI-enhanced patterns to identify boarding pass elements
4. **Vision Fallback**: Automatically falls back to Apple Vision if needed

### Boarding Pass Data Extraction

The new system can extract:
- ✈️ **Flight Information**: Number, airline, route
- 👤 **Passenger Details**: Name, seat assignment
- 🕒 **Schedule**: Departure/arrival times and dates
- 🚪 **Gate Information**: Gate, terminal details
- 🎫 **Booking Details**: Confirmation codes

### API Usage & Pricing

- **Cost**: ~$1 per 1,000 pages processed
- **Speed**: Up to 2,000 pages per minute
- **Limits**: 50MB file size, 1,000 pages max
- **Formats**: JPG, PNG, TIFF, PDF

## Technical Implementation

### Architecture Overview

```
BoardingPassScanner
├── MistralOCRService (Primary)
│   ├── API Integration
│   ├── Enhanced Parsing
│   └── Structured Analysis
└── Vision Framework (Fallback)
    ├── Traditional OCR
    └── Pattern Matching
```

### Key Components

1. **MistralOCRService**: Main AI-powered OCR service
2. **BoardingPassAnalyzer**: Smart document structure analysis  
3. **BoardingPassScanner**: Unified interface with fallback logic

### Error Handling

The system handles various scenarios:
- 🌐 **API Unavailable**: Falls back to Vision framework
- 🔑 **No API Key**: Automatically uses Vision framework
- 📊 **Low Confidence**: Tries alternative parsing methods
- ⚡ **Network Issues**: Graceful degradation with error messages

## Testing

### Verify OCR Quality

1. Use a real boarding pass image
2. Check console logs for processing method
3. Compare extracted data accuracy:
   - Mistral AI: Should extract most fields accurately
   - Vision: May miss some complex layouts

### Performance Comparison

| Feature | Mistral OCR | Vision Framework |
|---------|-------------|------------------|
| Accuracy | ~94.9% | ~80-85% |
| Complex Layouts | ✅ Excellent | ⚠️ Limited |
| Multilingual | ✅ Advanced | ✅ Good |
| Cost | ~$1/1000 pages | Free |
| Offline | ❌ No | ✅ Yes |

## Troubleshooting

### Common Issues

**"MISTRAL_API_KEY not found"**
- Verify API key is correctly set
- Check key format (should start with `mistral_`)
- Restart app after setting environment variable

**"API Error 401"**
- Invalid or expired API key
- Check key in Mistral dashboard
- Verify key permissions

**"API Error 429"**
- Rate limit exceeded
- Wait before retrying
- Consider upgrading plan

**Low extraction accuracy**
- Image quality may be poor
- Try higher resolution images
- Ensure boarding pass is clearly visible

### Debug Mode

Enable detailed logging by adding to your environment:
```bash
export MISTRAL_DEBUG=1
```

## Security Best Practices

⚠️ **Important Security Notes:**

1. **Never commit API keys to version control**
2. **Use environment variables in production**
3. **Rotate keys regularly**
4. **Monitor API usage for unusual activity**
5. **Use least-privilege access when possible**

### Recommended .gitignore entries:
```
# API Keys
*.plist
.env
*.key
```

## Migration from Vision-Only

If upgrading from the previous Vision-only implementation:

1. **No Code Changes Required**: Existing code continues to work
2. **Automatic Enhancement**: Better accuracy with no changes
3. **Gradual Rollout**: Test with API key, remove to revert
4. **Data Compatibility**: Same output format maintained

## Support

For issues with:
- **Mistral API**: Contact [Mistral Support](https://docs.mistral.ai/)
- **SkyLine Integration**: Check console logs and verify setup
- **Vision Framework**: Apple developer documentation

---

*Last updated: November 2024*
*Mistral OCR integration by Claude Code*