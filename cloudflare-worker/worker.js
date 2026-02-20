/**
 * Cloudflare Worker for SkyLine - Secure OpenRouter API Proxy
 *
 * This worker acts as a secure proxy between your iOS app and OpenRouter API,
 * keeping your API key safe on the server side.
 */

export default {
  async fetch(request, env, ctx) {
    // Handle CORS preflight requests
    if (request.method === 'OPTIONS') {
      return handleCORS();
    }

    // Only allow POST requests
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed' }, 405);
    }

    try {
      // Parse request body
      const body = await request.json();
      const { prompt, model, userId, maxTokens, imageBase64, stream } = body;

      // Validate required fields
      if (!prompt || !userId) {
        return jsonResponse({ error: 'Missing required fields: prompt, userId' }, 400);
      }

      // Validate prompt length (prevent abuse)
      if (prompt.length > 50000) { // Increased for image prompts
        return jsonResponse({ error: 'Prompt too long (max 50,000 characters)' }, 400);
      }

      // Rate limiting: Check requests per user per day
      const rateLimitResult = await checkRateLimit(env, userId);
      if (!rateLimitResult.allowed) {
        return jsonResponse({
          error: 'Rate limit exceeded',
          limit: rateLimitResult.limit,
          resetAt: rateLimitResult.resetAt
        }, 429);
      }

      // Don't allow streaming with images (vision models)
      if (stream && imageBase64) {
        return jsonResponse({ error: 'Streaming not supported with image requests' }, 400);
      }

      // Build messages based on whether image is provided
      let messages;
      if (imageBase64) {
        // Vision model request with image
        messages = [
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: prompt
              },
              {
                type: 'image_url',
                image_url: {
                  url: `data:image/jpeg;base64,${imageBase64}`
                }
              }
            ]
          }
        ];
      } else {
        // Text-only request
        messages = [
          {
            role: 'user',
            content: prompt
          }
        ];
      }

      // Build request body
      const requestBody = {
        model: model || 'openai/gpt-4o-mini', // Default to cost-effective model
        messages: messages,
        max_tokens: Math.min(maxTokens || 1000, 8000), // Cap at 8000 tokens for itinerary generation
        temperature: 0.1, // Lower temperature for boarding pass extraction
        stream: stream || false // Enable streaming if requested
      };

      // Add response_format for supported models to force JSON output (only for non-streaming)
      if (!stream && model && (model.includes('gpt-4') || model.includes('gpt-3.5'))) {
        requestBody.response_format = { type: 'json_object' };
      }

      // Call OpenRouter API
      const openRouterResponse = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.OPENROUTER_API_KEY}`,
          'Content-Type': 'application/json',
          'HTTP-Referer': env.APP_URL || 'https://skyline.app',
          'X-Title': 'SkyLine Flight Tracker'
        },
        body: JSON.stringify(requestBody)
      });

      // Check if OpenRouter request was successful
      if (!openRouterResponse.ok) {
        const errorText = await openRouterResponse.text();
        console.error('OpenRouter API error:', errorText);
        return jsonResponse({
          error: 'OpenRouter API error',
          details: errorText
        }, openRouterResponse.status);
      }

      // Increment rate limit counter (do this immediately, not after completion)
      await incrementRateLimit(env, userId);

      // Handle streaming vs non-streaming responses
      if (stream) {
        // Stream the response directly to the client
        return new Response(openRouterResponse.body, {
          status: 200,
          headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
          }
        });
      } else {
        // Non-streaming: wait for complete response
        const data = await openRouterResponse.json();

        // Return successful response
        return jsonResponse({
          success: true,
          data: data,
          usage: {
            requestsRemaining: rateLimitResult.remaining - 1,
            resetAt: rateLimitResult.resetAt
          }
        });
      }

    } catch (error) {
      console.error('Worker error:', error);
      return jsonResponse({
        error: 'Internal server error',
        message: error.message
      }, 500);
    }
  }
};

/**
 * Check rate limit for a user
 * Limit: 100 requests per user per day
 */
async function checkRateLimit(env, userId) {
  const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
  const key = `rate_limit:${userId}:${today}`;
  const limit = 100; // 100 requests per day

  try {
    const currentCount = await env.RATE_LIMIT_KV.get(key);
    const count = currentCount ? parseInt(currentCount) : 0;

    // Calculate reset time (midnight UTC)
    const tomorrow = new Date();
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    tomorrow.setUTCHours(0, 0, 0, 0);

    return {
      allowed: count < limit,
      remaining: Math.max(0, limit - count),
      limit: limit,
      resetAt: tomorrow.toISOString()
    };
  } catch (error) {
    console.error('Rate limit check error:', error);
    // If KV is not available, allow the request
    return {
      allowed: true,
      remaining: limit,
      limit: limit,
      resetAt: new Date().toISOString()
    };
  }
}

/**
 * Increment rate limit counter for a user
 */
async function incrementRateLimit(env, userId) {
  const today = new Date().toISOString().split('T')[0];
  const key = `rate_limit:${userId}:${today}`;

  try {
    const currentCount = await env.RATE_LIMIT_KV.get(key);
    const count = currentCount ? parseInt(currentCount) + 1 : 1;

    // Set expiration to end of day (86400 seconds = 24 hours)
    await env.RATE_LIMIT_KV.put(key, count.toString(), {
      expirationTtl: 86400
    });
  } catch (error) {
    console.error('Rate limit increment error:', error);
    // Continue even if increment fails
  }
}

/**
 * Helper function to return JSON response with CORS headers
 */
function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status: status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '86400'
    }
  });
}

/**
 * Handle CORS preflight requests
 */
function handleCORS() {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '86400'
    }
  });
}
