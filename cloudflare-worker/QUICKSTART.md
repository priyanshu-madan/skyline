# Quick Start Guide

Get your SkyLine OpenRouter proxy up and running in 5 minutes.

## Prerequisites

- Node.js installed (v16 or later)
- Cloudflare account (free tier is fine)
- OpenRouter API key ([Get one here](https://openrouter.ai/keys))

## Step-by-Step Setup

### 1. Install Wrangler

```bash
npm install -g wrangler
```

### 2. Navigate to the worker directory

```bash
cd cloudflare-worker
```

### 3. Run the automated setup script

```bash
./deploy.sh
```

This script will:
- Check if you're logged into Cloudflare (and log you in if not)
- Create a KV namespace for rate limiting
- Prompt you to set your OpenRouter API key
- Deploy the worker

### 4. Update the KV namespace ID

After the first run, the script will show you a KV namespace ID like:

```
{ binding = "RATE_LIMIT_KV", id = "abc123def456..." }
```

Copy the `id` value and update `wrangler.toml`:

```toml
[[kv_namespaces]]
binding = "RATE_LIMIT_KV"
id = "abc123def456..."  # Replace YOUR_KV_NAMESPACE_ID with this
```

### 5. Run the setup script again

```bash
./deploy.sh
```

This time it will deploy successfully!

### 6. Copy your worker URL

After deployment, you'll see:

```
✨ Published skyline-openrouter-proxy
   https://skyline-openrouter-proxy.your-subdomain.workers.dev
```

### 7. Update your iOS app

Open `SkyLine/Services/OpenRouterService.swift` and update the URL:

```swift
private let workerURL = "https://skyline-openrouter-proxy.your-subdomain.workers.dev"
```

## Testing

Test your worker is working:

```bash
curl -X POST https://your-worker-url.workers.dev \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Say hello in 5 words",
    "userId": "test-user",
    "model": "openai/gpt-4o-mini"
  }'
```

Expected response:

```json
{
  "success": true,
  "data": {
    "choices": [{
      "message": {
        "content": "Hello! How can I help?"
      }
    }]
  },
  "usage": {
    "requestsRemaining": 99,
    "resetAt": "2024-01-02T00:00:00.000Z"
  }
}
```

## View Live Logs

```bash
wrangler tail
```

Then make requests from your iOS app and watch them in real-time!

## Common Issues

### "KV namespace not found"

Make sure you updated the `id` in `wrangler.toml` after creating the namespace.

### "Unauthorized" from OpenRouter

Your API key might not be set correctly. Run:

```bash
wrangler secret put OPENROUTER_API_KEY
```

### Rate limit not working

Check that the KV namespace binding name in `wrangler.toml` matches the one in `worker.js` (should be `RATE_LIMIT_KV`).

## Cost Breakdown

**Cloudflare Workers (Free Tier):**
- 100,000 requests/day
- 10ms CPU time per request
- KV reads: 100,000/day
- KV writes: 1,000/day

**OpenRouter (Pay as you go):**
- GPT-4o-mini: ~$0.15 per 1M input tokens
- Average request: ~500 tokens ≈ $0.0005
- 100 requests/user/day = ~$0.05/user/day

**Example costs for 1,000 users:**
- Cloudflare: $0/month (free tier)
- OpenRouter: ~$50/day = ~$1,500/month

💡 **Tip:** Consider upgrading to paid tier or adjusting rate limits based on actual usage.

## Next Steps

1. ✅ Deploy worker
2. ✅ Update iOS app with worker URL
3. 📱 Test from your app
4. 📊 Monitor usage in Cloudflare dashboard
5. 🎯 Adjust rate limits if needed

## Need Help?

Check the full README.md for detailed documentation.
