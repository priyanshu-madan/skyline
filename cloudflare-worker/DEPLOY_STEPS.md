# Manual Deployment Steps

Follow these steps exactly to deploy your worker:

## Step 1: Login to Cloudflare

```bash
cd /Users/priyanshumadan/Development/skyline/cloudflare-worker
wrangler login
```

- This will open your browser
- Click "Allow" to authorize Wrangler
- Browser will show "Successfully logged in"

## Step 2: Create KV Namespace

```bash
wrangler kv:namespace create "RATE_LIMIT_KV"
```

- This will output something like:
  ```
  { binding = "RATE_LIMIT_KV", id = "abc123def456..." }
  ```
- **IMPORTANT**: Copy the `id` value

## Step 3: Update wrangler.toml

Open `wrangler.toml` and replace `YOUR_KV_NAMESPACE_ID` with the ID from Step 2:

```toml
[[kv_namespaces]]
binding = "RATE_LIMIT_KV"
id = "abc123def456..."  # Replace this with your actual ID
```

## Step 4: Set OpenRouter API Key

```bash
wrangler secret put OPENROUTER_API_KEY
```

- When prompted, paste your OpenRouter API key
- Press Enter

## Step 5: Deploy

```bash
wrangler deploy
```

- This will deploy your worker
- You'll see output like:
  ```
  ✨ Published skyline-openrouter-proxy
     https://skyline-openrouter-proxy.your-subdomain.workers.dev
  ```
- **COPY THIS URL!**

## Step 6: Update iOS App

Open `SkyLine/Services/OpenRouterService.swift` and update line 47:

```swift
private let workerURL = "https://skyline-openrouter-proxy.your-subdomain.workers.dev"
```

## Step 7: Test

```bash
curl -X POST https://your-worker-url.workers.dev \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Say hello!",
    "userId": "test-user",
    "model": "openai/gpt-4o-mini"
  }'
```

Should return JSON with the AI response.

## Done! 🎉

Your OpenRouter API is now secured behind your Cloudflare Worker.

View live logs:
```bash
wrangler tail
```
