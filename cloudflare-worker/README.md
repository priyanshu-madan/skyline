# SkyLine OpenRouter API Proxy

Cloudflare Worker that securely proxies requests to OpenRouter API, keeping your API key safe.

## Features

- 🔒 **Secure**: API key stored server-side, never exposed to client
- 🚦 **Rate Limiting**: 100 requests per user per day
- 💰 **Cost Protection**: Max token limits to prevent expensive requests
- 🌍 **Global CDN**: Fast response times worldwide
- 📊 **Usage Tracking**: Monitor requests remaining per user

## Setup Instructions

### 1. Install Wrangler CLI

```bash
npm install -g wrangler
```

### 2. Login to Cloudflare

```bash
wrangler login
```

This will open a browser window to authenticate with Cloudflare.

### 3. Create KV Namespace for Rate Limiting

```bash
wrangler kv:namespace create "RATE_LIMIT_KV"
```

This will output something like:
```
🌀 Creating namespace with title "skyline-openrouter-proxy-RATE_LIMIT_KV"
✨ Success!
Add the following to your wrangler.toml:
{ binding = "RATE_LIMIT_KV", id = "abc123..." }
```

Copy the `id` value and update it in `wrangler.toml`.

### 4. Set Your OpenRouter API Key

```bash
wrangler secret put OPENROUTER_API_KEY
```

When prompted, paste your OpenRouter API key. This stores it securely in Cloudflare.

### 5. Deploy the Worker

```bash
wrangler deploy
```

After deployment, you'll see output like:
```
✨ Built successfully
🚀 Published skyline-openrouter-proxy
   https://skyline-openrouter-proxy.your-subdomain.workers.dev
```

Copy this URL - you'll need it for your iOS app.

## Testing the Worker

Test with curl:

```bash
curl -X POST https://skyline-openrouter-proxy.your-subdomain.workers.dev \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Extract flight info: AA123 from LAX to JFK on Dec 25",
    "model": "openai/gpt-4o-mini",
    "userId": "test-user-123",
    "maxTokens": 500
  }'
```

Expected response:
```json
{
  "success": true,
  "data": {
    "choices": [...],
    "usage": {...}
  },
  "usage": {
    "requestsRemaining": 99,
    "resetAt": "2024-01-02T00:00:00.000Z"
  }
}
```

## API Documentation

### Endpoint

```
POST https://your-worker-url.workers.dev
```

### Request Body

```json
{
  "prompt": "Your prompt here",
  "model": "openai/gpt-4o-mini",  // Optional, defaults to gpt-4o-mini
  "userId": "user-id",             // Required for rate limiting
  "maxTokens": 1000                // Optional, defaults to 1000, max 2000
}
```

### Response (Success)

```json
{
  "success": true,
  "data": {
    "id": "gen-abc123",
    "model": "openai/gpt-4o-mini",
    "choices": [
      {
        "message": {
          "role": "assistant",
          "content": "Response text here"
        },
        "finish_reason": "stop"
      }
    ],
    "usage": {
      "prompt_tokens": 50,
      "completion_tokens": 100,
      "total_tokens": 150
    }
  },
  "usage": {
    "requestsRemaining": 99,
    "resetAt": "2024-01-02T00:00:00.000Z"
  }
}
```

### Response (Rate Limit Exceeded)

```json
{
  "error": "Rate limit exceeded",
  "limit": 100,
  "resetAt": "2024-01-02T00:00:00.000Z"
}
```

## Rate Limiting

- **Limit**: 100 requests per user per day
- **Reset**: Midnight UTC
- **Storage**: Cloudflare KV (Key-Value store)
- **Tracking**: By `userId` from request

## Cost Protection

- Default max tokens: 1000
- Hard cap: 2000 tokens
- Default model: `openai/gpt-4o-mini` (cost-effective)
- Prompt length limit: 10,000 characters

## Monitoring

View logs in real-time:

```bash
wrangler tail
```

## Updating the Worker

After making changes to `worker.js`:

```bash
wrangler deploy
```

## Security Notes

1. **Never commit your API key** - Always use `wrangler secret put`
2. **Rate limiting protects against abuse** - 100 req/day per user
3. **Token limits prevent runaway costs** - Max 2000 tokens per request
4. **CORS enabled** - Only for your iOS app (update APP_URL in wrangler.toml)

## Troubleshooting

### "KV namespace not found"
Make sure you created the KV namespace and updated the ID in `wrangler.toml`.

### "Unauthorized" from OpenRouter
Check that you set the API key correctly:
```bash
wrangler secret put OPENROUTER_API_KEY
```

### Rate limit not working
Verify KV namespace is bound correctly in `wrangler.toml`.

## iOS App Integration

See the Swift service file: `SkyLine/Services/OpenRouterService.swift`

Example usage:
```swift
let result = try await OpenRouterService.shared.sendPrompt(
    "Extract flight details from this text...",
    model: "openai/gpt-4o-mini"
)
```

## Cost Estimates

Using `openai/gpt-4o-mini`:
- ~$0.15 per 1M input tokens
- ~$0.60 per 1M output tokens
- Average request: ~500 tokens = $0.0005
- 100 requests/day/user = ~$0.05 per user per day
- 1000 users = ~$50/day

Consider upgrading rate limits based on usage patterns.

## Support

For issues or questions:
1. Check Cloudflare Workers dashboard
2. View logs with `wrangler tail`
3. Check OpenRouter status page

## License

Part of the SkyLine Flight Tracker project.
