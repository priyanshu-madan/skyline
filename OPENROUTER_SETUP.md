# OpenRouter API Key Setup

## Configuration Steps:

1. **Get your OpenRouter API key** from https://openrouter.ai/

2. **Update Info.plist**:
   - Open `SkyLine/Info.plist` 
   - Replace `YOUR_OPENROUTER_API_KEY_HERE` with your actual API key:
   
   ```xml
   <key>OPENROUTER_API_KEY</key>
   <string>sk-or-v1-your-actual-api-key-here</string>
   ```

3. **Build and run** - The OpenRouter service will automatically load the API key from Info.plist

## Features:
- ✅ Multi-LLM support (GPT-4 Vision, Claude 3.5 Sonnet, GPT-4o Mini)
- ✅ Automatic fallbacks (OpenRouter → Apple Intelligence → Vision Framework)
- ✅ Cost tracking and optimization
- ✅ Secure configuration via Info.plist

## Usage:
- Press "+" button in Flights tab
- Select "Scan Boarding Pass" 
- Choose photo from camera or gallery
- Enjoy enhanced AI-powered parsing!