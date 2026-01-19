# Get Your OpenRouter API Key

## The Issue

The OpenRouter API key in your `Info.plist` is invalid/expired, causing the 401 "User not found" error.

## Quick Fix (5 minutes)

### 1. Get a New Key

**Go to**: [openrouter.ai/keys](https://openrouter.ai/keys)

**Sign in or create account** (it's free!)

**Create a new API key**:
- Click **"Create Key"**
- Name it: "SkyLine App"
- Copy the key (starts with `sk-or-v1-...`)

### 2. Update Info.plist

Open `SkyLine/Info.plist` and replace:

```xml
<key>OPENROUTER_API_KEY</key>
<string>YOUR_NEW_OPENROUTER_KEY_HERE</string>
```

With your actual key:

```xml
<key>OPENROUTER_API_KEY</key>
<string>sk-or-v1-YOUR-ACTUAL-KEY-HERE</string>
```

### 3. Test the Key (Optional)

In Terminal, run:

```bash
curl https://openrouter.ai/api/v1/auth/key \
  -H "Authorization: Bearer YOUR_KEY_HERE"
```

**Good response** (key is valid):
```json
{
  "data": {
    "label": "SkyLine App",
    "usage": 0,
    "limit": null,
    ...
  }
}
```

**Bad response** (key is invalid):
```json
{
  "error": {
    "message": "User not found.",
    "code": 401
  }
}
```

### 4. Run the App

1. Build and run
2. Create a trip without an image
3. Wait for "Generating image..."
4. Should work now! ✅

## Free Tier Limits

OpenRouter's free tier includes:
- Limited requests per day
- Access to free models (like `gemini-2.0-flash-exp:free`)
- Perfect for development and testing

For production, consider:
- Upgrading to paid tier for higher limits
- Monitoring usage via OpenRouter dashboard
- Implementing user quotas in your app

## Troubleshooting

### Still getting 401?
- Double-check the key is copied correctly (no extra spaces)
- Verify it's the `OPENROUTER_API_KEY` field, not another field
- Try creating a fresh key

### Other errors?
- Check OpenRouter status: [status.openrouter.ai](https://status.openrouter.ai)
- Review the console logs for specific error messages
- Try a different model if needed

## Why Did the Old Key Stop Working?

Possible reasons:
1. Key was revoked or deleted
2. OpenRouter account was deactivated
3. Key expired (if it was a temporary/demo key)
4. Security issue detected by OpenRouter

Creating a fresh key will resolve this!

---

**Next Steps**:
1. Get your new key from [openrouter.ai/keys](https://openrouter.ai/keys)
2. Update `Info.plist`
3. Test the app
4. Enjoy AI-generated trip images! 🎨
