# Lingua image proxy

A tiny Express service that generates card illustrations with OpenAI and returns
**raw PNG bytes**. It keeps your `OPENAI_API_KEY` server-side so it never ships
in the Flutter client.

## Gemini (Imagen 3) image proxy

`gemini_proxy_server.js` generates flashcard images with Google Imagen 3.

```bash
cd server
cp .env.example .env        # put GEMINI_API_KEY=AIza... (from aistudio.google.com/apikey)
npm install
npm run gemini              # http://localhost:3000  (POST /api/generate-image)
```

Then run the app pointed at it:

```bash
flutter run -d chrome \
  --dart-define=IMAGE_BACKEND=http://localhost:3000/api/generate-image
```

The app POSTs `{ "prompt": ... }` and the proxy returns `{ "base64": ... }`,
which the client decodes into the card image. The public GitHub Pages build
can't reach `localhost` — to use Imagen on the hosted app you'd deploy this
proxy over HTTPS and build with that URL.

## OpenAI image proxy — run locally

```bash
cd server
cp .env.example .env        # then put your real OPENAI_API_KEY in .env
npm install
npm run dev                 # http://localhost:8080  (auto-reload)
# or: npm start
```

Smoke-test it:

```bash
# health
curl http://localhost:8080/health

# generate -> writes out.png
curl -X POST http://localhost:8080/image \
  -H "Content-Type: application/json" \
  -d '{"prompt":"A clear, minimalist illustration of a book","size":"1024x1024"}' \
  --output out.png
```

## API

| Method | Path      | Body                       | Response            |
|--------|-----------|----------------------------|---------------------|
| POST   | `/image`  | `{ prompt, size? }`        | `image/png` (bytes) |
| GET    | `/health` | —                          | `{ ok: true }`      |

Errors return JSON `{ "error": "..." }` with a 4xx/5xx status. `size` accepts
`1024x1024` (default), `1024x1536`, `1536x1024`, or `auto`.

`POST /image` is rate-limited per client IP (default **30 requests / 15 min**,
tune with `RATE_MAX` and `RATE_WINDOW_MS`). Over the limit returns **429** with
`RateLimit-*` headers. When running behind a load balancer, set `TRUST_PROXY` so
the limiter keys on the real client IP.

## Connect the app

Point the Flutter client at this proxy at run time — no code change:

```bash
flutter run -d chrome \
  --dart-define=IMAGE_BACKEND=http://localhost:8080/image
```

That flips `kImageBackendEndpoint` in `lib/app_services.dart`, which swaps the
demo provider for `ProxyImageGenProvider`. The app POSTs `{ prompt, size }` and
reads the PNG bytes straight into the card's visual anchor (stored as a BLOB).

> For web, make sure `CORS_ORIGIN` includes the app's origin (or `*` in dev),
> otherwise the browser will block the request.

## Docker

```bash
cd server
docker build -t lingua-image-proxy .
docker run --rm -p 8080:8080 \
  -e OPENAI_API_KEY=sk-... \
  -e CORS_ORIGIN=https://lingua.yourdomain.com \
  lingua-image-proxy
```

The image is a multi-stage `node:20-alpine` build that installs prod
dependencies only, runs as the non-root `node` user, and ships a `HEALTHCHECK`
that polls `/health`. Pass config via `-e` (or `--env-file .env`).

Or with Compose (reads `.env` automatically):

```bash
cd server
cp .env.example .env   # add OPENAI_API_KEY
docker compose up --build
```

## CI/CD

Two GitHub Actions workflows are in [`.github/workflows`](../.github/workflows):

- **docker-image.yml** — on pushes touching `server/**`, builds this image and
  pushes it to GHCR (`ghcr.io/<owner>/<repo>/image-proxy`) tagged with the commit
  SHA and `latest`. Uses the built-in `GITHUB_TOKEN`; no extra secrets needed.
- **flutter-ci.yml** — runs `flutter analyze` + `flutter test` (with Drift
  codegen) on the app.

## Deploy

Any Node 20+ host or container platform works (Render, Fly.io, Railway, Cloud
Run, a VM). Provide `OPENAI_API_KEY`, and set `PORT`, `CORS_ORIGIN`, `RATE_MAX`,
`RATE_WINDOW_MS`, and `TRUST_PROXY` as needed. Always terminate TLS in front of
it (HTTPS) before exposing it publicly.
