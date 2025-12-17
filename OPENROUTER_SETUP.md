# OpenRouter API Key Setup

## ⚠️ SECURITY WARNING
**NEVER commit API keys to Git!** This file contains placeholders only.

## Configuration Steps:

1. **Get your OpenRouter API key** from https://openrouter.ai/

2. **Update Info.plist LOCALLY**:
   - Open `SkyLine/Info.plist` 
   - Replace `YOUR_OPENROUTER_API_KEY_HERE` with your actual API key:
   
   ```xml
   <key>OPENROUTER_API_KEY</key>
   <string>sk-or-v1-your-actual-api-key-here</string>
   ```

3. **IMPORTANT**: The template Info.plist is tracked, but be careful not to commit your real API key!

4. **Build and run** - The OpenRouter service will automatically load the API key from Info.plist

## Security Best Practices:
- ✅ Info.plist with real keys is ignored by Git
- ✅ Use environment variables in CI/CD
- ✅ Regularly rotate API keys
- ✅ Monitor API usage for anomalies
- ❌ NEVER commit real API keys to version control

## Features:
- ✅ Multi-LLM support (GPT-4o, Claude 3.5 Sonnet, GPT-4o Mini)
- ✅ Automatic fallbacks (OpenRouter → Apple Intelligence → Vision Framework)
- ✅ Cost tracking and optimization
- ✅ Secure local configuration
- ✅ Enhanced date parsing with boarding pass formats

## Usage:
- Press "+" button in Flights tab
- Select "Scan Boarding Pass" 
- Choose photo from camera or gallery
- Enjoy enhanced AI-powered parsing!

## Troubleshooting:
- If you see "API key not configured" - check Info.plist has your real key
- If parsing fails - check OpenRouter dashboard for API usage/errors