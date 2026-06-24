import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';

// Load environment variables from a .env file
dotenv.config();

const app = express();

// Allow the Flutter app to call this proxy. Lock CORS_ORIGIN down to your app's
// origin in production (comma-separated list supported); defaults to any.
const origins = (process.env.CORS_ORIGIN ?? '*').split(',').map((s) => s.trim());
app.use(cors({ origin: origins.includes('*') ? true : origins }));
app.use(express.json({ limit: '64kb' }));

// Get your key from Google AI Studio (https://aistudio.google.com/apikey) and
// put it in a .env file:  GEMINI_API_KEY=AIza...
const API_KEY = process.env.GEMINI_API_KEY;
if (!API_KEY) {
  console.warn('[startup] GEMINI_API_KEY is not set — /api/generate-image will error.');
}

app.get('/health', (_req, res) => res.json({ ok: true }));

app.post('/api/generate-image', async (req, res) => {
  try {
    const { prompt } = req.body ?? {};
    if (!prompt) return res.status(400).json({ error: 'Prompt is required' });
    if (!API_KEY) return res.status(503).json({ error: 'GEMINI_API_KEY not configured' });

    console.log(`Generating image for prompt: "${prompt}"`);

    // Google AI Studio endpoint for Imagen 3
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-001:predict?key=${API_KEY}`;

    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        instances: [{ prompt }],
        parameters: {
          sampleCount: 1,
          aspectRatio: '16:9', // wide ratio for the flashcard UI
        },
      }),
    });

    const data = await response.json();
    if (!response.ok) {
      console.error('Gemini API Error:', data);
      throw new Error(data.error?.message || 'Failed to generate image');
    }

    const base64Image = data?.predictions?.[0]?.bytesBase64Encoded;
    if (!base64Image) throw new Error('No image returned by the model');

    res.json({ base64: base64Image });
  } catch (error) {
    console.error('Server error:', error.message);
    res.status(502).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Gemini image proxy running at http://localhost:${PORT}`);
  console.log(`  POST /api/generate-image  { prompt }  -> { base64 }`);
});
