#!/bin/bash

# SkyLine Cloudflare Worker Deployment Script

echo "🚀 SkyLine OpenRouter Worker Deployment"
echo "========================================"
echo ""

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo "❌ Wrangler CLI not found!"
    echo "Install it with: npm install -g wrangler"
    exit 1
fi

echo "✅ Wrangler CLI found"
echo ""

# Check if logged in
echo "Checking Cloudflare authentication..."
if ! wrangler whoami &> /dev/null; then
    echo "⚠️  Not logged in to Cloudflare"
    echo "Running: wrangler login"
    wrangler login
else
    echo "✅ Logged in to Cloudflare"
fi
echo ""

# Check if KV namespace is configured
if grep -q "YOUR_KV_NAMESPACE_ID" wrangler.toml; then
    echo "⚠️  KV namespace not configured yet!"
    echo ""
    echo "Creating KV namespace for rate limiting..."
    wrangler kv:namespace create "RATE_LIMIT_KV"
    echo ""
    echo "⚠️  IMPORTANT: Copy the 'id' value from above and update it in wrangler.toml"
    echo "Then run this script again."
    exit 1
fi

echo "✅ KV namespace configured"
echo ""

# Check if API key is set
echo "Checking if OPENROUTER_API_KEY is set..."
echo "(If prompted, paste your OpenRouter API key)"
echo ""
if ! wrangler secret list | grep -q "OPENROUTER_API_KEY"; then
    echo "⚠️  API key not set"
    echo "Setting OPENROUTER_API_KEY..."
    wrangler secret put OPENROUTER_API_KEY
else
    echo "✅ API key already set"
    read -p "Do you want to update it? (y/N): " update_key
    if [[ $update_key == "y" || $update_key == "Y" ]]; then
        wrangler secret put OPENROUTER_API_KEY
    fi
fi
echo ""

# Deploy
echo "🚀 Deploying worker..."
wrangler deploy

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📝 Next steps:"
echo "1. Copy the worker URL from above"
echo "2. Update workerURL in SkyLine/Services/OpenRouterService.swift"
echo "3. Test with: wrangler tail (to see live logs)"
echo ""
echo "🧪 Test your worker:"
echo 'curl -X POST https://your-worker-url.workers.dev \\'
echo '  -H "Content-Type: application/json" \\'
echo '  -d '"'"'{"prompt":"Say hello","userId":"test","model":"openai/gpt-4o-mini"}'"'"''
echo ""
