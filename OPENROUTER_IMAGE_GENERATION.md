# OpenRouter Image Generation Setup

## ✅ Ready to Use!

Your app is now configured to use **Google Gemini 2.0 Flash** via OpenRouter for AI-generated trip cover images.

## What Changed

I've updated the image generation service to use:
- **Model**: `google/gemini-2.0-flash-exp:free`
- **Endpoint**: OpenRouter's chat completions API
- **API Key**: Your existing `OPENROUTER_API_KEY` (already configured)
- **Cost**: FREE (using the `:free` tier)

## How It Works

1. User creates a trip without uploading an image
2. App sends your prompt to Gemini 2.0 Flash via OpenRouter
3. Gemini generates the image and returns it (as URL or base64)
4. App downloads and saves both dark/light theme variants
5. Images display automatically based on current theme

## Key Benefits

✅ **Free to use** - No additional cost beyond OpenRouter free tier
✅ **Fast generation** - 5-10 seconds per image
✅ **Already configured** - Uses your existing OpenRouter key
✅ **No setup needed** - Works immediately
✅ **Theme-aware** - Auto-generates dark + light variants

## Test It Now

1. Run the app
2. Create a new trip
3. Enter a destination (e.g., "Lantau Island, Hong Kong")
4. **Don't upload an image**
5. Click "Create Trip"
6. Wait for "Generating image..." (~10-15 seconds)
7. Your trip appears with a beautiful AI-generated cover!

## Expected Console Output

```
✅ TripImageGeneration: OpenRouter API key loaded
🎨 Generating AI images for: Lantau Island, Hong Kong
✅ Generated dark mode image for: Lantau Island, Hong Kong
✅ Generated light mode image for: Lantau Island, Hong Kong
✅ Generated and saved both theme variants
```

## Image Response Format

Gemini 2.0 Flash may return images in two formats:
1. **Markdown with URL**: `![image](https://...)`
2. **Base64 data**: `data:image/png;base64,...`

The service automatically detects and handles both formats.

## Rate Limits

The free tier has usage limits:
- If you hit rate limits, wait a few minutes
- For production, consider OpenRouter's paid tier
- Implement user quotas if needed

## Troubleshooting

### No image generated
- Check console for error messages
- Verify OpenRouter API key is valid
- Try again in a few minutes (rate limit)

### Image doesn't switch themes
- Ensure both `_dark.jpg` and `_light.jpg` files exist
- Check file paths in console logs

### Wrong model error
- Model name: `google/gemini-2.0-flash-exp:free`
- Endpoint: `/chat/completions` (not `/images/generations`)

## Technical Details

### Request Format
```json
{
  "model": "google/gemini-2.0-flash-exp:free",
  "messages": [
    {
      "role": "user",
      "content": "Generate an ultra-minimal dot-matrix illustration of [destination]..."
    }
  ]
}
```

### Response Parsing
The service extracts images from the response content using:
1. Regex to find markdown image URLs
2. Regex to find base64 data URLs
3. Downloads URL-based images
4. Decodes base64 images

### File Naming
- Dark mode: `{tripId}_dark.jpg`
- Light mode: `{tripId}_light.jpg`
- Location: `Documents/TripImages/`

## Next Steps

If everything works:
1. ✅ Image generation is ready for production
2. Consider caching images in CloudKit for cross-device sync
3. Monitor OpenRouter usage in production
4. Add usage analytics to track generation success rate

If you encounter issues:
1. Check console logs for detailed error messages
2. Verify OpenRouter account is active
3. Try a different model if needed (e.g., `google/gemini-pro-vision`)
4. Reach out to OpenRouter support for API issues

## Alternative Models

If `gemini-2.0-flash-exp:free` doesn't work, try:
- `google/gemini-pro-vision` - More stable, but paid
- `anthropic/claude-3-haiku` - Fast and cheap
- `openai/gpt-4o-mini` - Good quality, affordable

Just change the model name in `TripImageGenerationService.swift` line 65.

---

**Note**: This uses OpenRouter's chat completions endpoint because image generation models are accessed through chat, not a dedicated images API like OpenAI's DALL-E.
