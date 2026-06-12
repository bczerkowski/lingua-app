import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';

import imageRoute from './imageRoute.js';

const app = express();

// Behind a proxy/load balancer (Render, Fly, Cloud Run, nginx) so the rate
// limiter and logs see the real client IP rather than the proxy's.
app.set('trust proxy', Number(process.env.TRUST_PROXY ?? 1));

// Allow the Flutter web app to call this proxy. Lock CORS_ORIGIN down to your
// app's origin in production (comma-separated list supported).
const origins = (process.env.CORS_ORIGIN ?? '*')
  .split(',')
  .map((s) => s.trim());
app.use(cors({ origin: origins.includes('*') ? true : origins }));

app.use(express.json({ limit: '64kb' }));

// Image generation is the expensive, abuse-prone endpoint — rate-limit it.
// Defaults: 30 requests per IP per 15 minutes. Tune via env.
const imageLimiter = rateLimit({
  windowMs: Number(process.env.RATE_WINDOW_MS ?? 15 * 60 * 1000),
  max: Number(process.env.RATE_MAX ?? 30),
  standardHeaders: true,
  legacyHeaders: false,
  // Don't count CORS preflight requests against the limit.
  skip: (req) => req.method === 'OPTIONS',
  message: { error: 'Too many image requests, please try again later.' },
});

app.get('/health', (_req, res) => res.json({ ok: true }));
app.use('/image', imageLimiter);
app.use('/', imageRoute);

if (!process.env.OPENAI_API_KEY) {
  console.warn('[startup] OPENAI_API_KEY is not set — /image will return errors.');
}

const port = Number(process.env.PORT ?? 8080);
app.listen(port, () => {
  console.log(`Lingua image proxy listening on http://localhost:${port}`);
  console.log(`  POST /image   { prompt, size }  -> image/png`);
  console.log(`  GET  /health`);
});
