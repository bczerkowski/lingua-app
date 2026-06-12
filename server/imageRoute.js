import express from 'express';
import OpenAI from 'openai';

const router = express.Router();

// Lazily create the OpenAI client so the server still boots (and /health works)
// when no key is configured — the route then returns a clear 503 instead.
let _openai;
function getClient() {
  if (!process.env.OPENAI_API_KEY) return null;
  _openai ??= new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  return _openai;
}

const ALLOWED_SIZES = new Set(['1024x1024', '1024x1536', '1536x1024', 'auto']);

/**
 * POST /image
 * Body: { prompt: string, size?: string }
 * Returns: raw PNG bytes (Content-Type: image/png)
 *
 * Matches the Flutter client `ProxyImageGenProvider`, which posts
 * { prompt, size } and reads the response as bytes.
 */
router.post('/image', async (req, res) => {
  const { prompt, size = '1024x1024' } = req.body ?? {};

  if (typeof prompt !== 'string' || prompt.trim().length === 0) {
    return res.status(400).json({ error: 'A non-empty "prompt" is required.' });
  }
  if (prompt.length > 4000) {
    return res.status(400).json({ error: 'Prompt is too long (max 4000 chars).' });
  }
  const requestedSize = ALLOWED_SIZES.has(size) ? size : '1024x1024';

  const openai = getClient();
  if (!openai) {
    return res.status(503).json({
      error: 'Image backend not configured (OPENAI_API_KEY missing).',
    });
  }

  try {
    const result = await openai.images.generate({
      model: 'gpt-image-1',
      prompt,
      size: requestedSize,
      n: 1,
    });

    const b64 = result?.data?.[0]?.b64_json;
    if (!b64) {
      return res.status(502).json({ error: 'Image service returned no image.' });
    }

    const png = Buffer.from(b64, 'base64');
    res.set('Content-Type', 'image/png');
    res.set('Cache-Control', 'no-store');
    return res.send(png);
  } catch (err) {
    // Surface a safe message; log the full error server-side.
    console.error('[image] generation failed:', err?.message ?? err);
    const status = err?.status && err.status >= 400 && err.status < 600 ? err.status : 502;
    return res.status(status).json({
      error: err?.message ?? 'Image generation failed.',
    });
  }
});

export default router;
