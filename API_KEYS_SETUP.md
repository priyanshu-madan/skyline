# API Keys Setup

## ⚠️ Security Notice

**NEVER commit API keys to Git!** This project requires API keys stored in `Info.plist`, but they should be kept private.

## Setup Instructions

### 1. Update Info.plist Locally

After cloning this repository, update `SkyLine/Info.plist` with your actual API keys:

```xml
<key>OPENROUTER_API_KEY</key>
<string>YOUR_ACTUAL_KEY_HERE</string>

<key>MISTRAL_API_KEY</key>
<string>YOUR_ACTUAL_KEY_HERE</string>
```

### 2. DO NOT Commit These Changes

The `Info.plist` file in the repository contains placeholder values. Keep it that way!

**Before committing:**
```bash
# Check what you're about to commit
git status
git diff SkyLine/Info.plist

# If Info.plist shows API key changes, DO NOT commit it
git restore SkyLine/Info.plist
```

### 3. Get Your API Keys

**OpenRouter:**
- Sign up at https://openrouter.ai
- Go to https://openrouter.ai/keys
- Create a new API key
- Add credits to your account

**Mistral AI:**
- Sign up at https://console.mistral.ai
- Generate an API key in the dashboard

## Current API Key Usage

**Note:** Since the image generation feature now uses **local on-device generation**, the OpenRouter API key is **no longer required** for the app to function. It's kept in the configuration for potential future use.

The app works perfectly without any API keys for trip cover image generation!

## Best Practices

1. ✅ Use environment-specific config files (`.gitignore`d)
2. ✅ Never hardcode secrets in source code
3. ✅ Rotate keys if accidentally exposed
4. ✅ Use placeholder values in committed files
5. ❌ Never commit Info.plist with real API keys
6. ❌ Never share API keys in screenshots or documentation

## If You Accidentally Expose a Key

1. **Immediately revoke** the exposed key from the provider's dashboard
2. **Generate a new key**
3. **Remove from Git history** using:
   ```bash
   git commit --amend  # if just committed
   git push --force    # update remote
   ```
4. **Update locally** with the new key

---

**Remember:** The app works perfectly without any API keys for core functionality!
