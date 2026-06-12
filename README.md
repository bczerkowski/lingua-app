# Lingua — Polish ⇄ English Dictionary + SRS Flashcards

A cross-platform Flutter app that is both a fast bilingual reference dictionary
and an Anki-style spaced-repetition learning tool. Offline-first (SQLite), with
native TTS, AI image generation (with a manual fallback), and bulk import.

## Run it

Prereqs: Flutter SDK (this project was scaffolded with the SDK at `C:\flutter`).

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates database.g.dart
flutter run -d chrome            # web (uses web/sqlite3.wasm + web/drift_worker.js)
# or: flutter run -d <android|ios|macos|linux>   # native uses file-backed SQLite
```

The first launch seeds a sample Polish–English deck from
`assets/sample_deck.json`.

> Windows desktop (`-d windows`) needs Visual Studio with the "Desktop
> development with C++" workload + Windows Developer Mode (symlink support).
> The `windows/` folder was removed during scaffolding; run
> `flutter create . --platforms windows` to add it back once those are installed.

## Verified working

- `flutter analyze` → no issues
- `flutter test` → 5/5 SRS unit tests pass (`test/srs_scheduler_test.dart`)
- Ran on Chrome (release web): DB seeds, Dictionary search/promote/TTS,
  Study flip + SM-2 grading, Editor CRUD + image fallback.

## Architecture

```
lib/
├── data/
│   ├── db/
│   │   ├── tables.dart            Drift tables (Catalogues, Cards)
│   │   ├── database.dart          DAO queries (search, due queue, CRUD)
│   │   ├── database.g.dart        GENERATED (build_runner)
│   │   └── connection/            platform-conditional executor (native vs web)
│   └── seed.dart                  first-run sample-deck loader
├── services/
│   ├── srs/srs_scheduler.dart     modified SM-2 (pure, unit-tested)
│   ├── tts/tts_service.dart       native TTS (pl-PL / en-US)
│   ├── ai/prompt_builder.dart     structured DALL·E prompt
│   └── ai/image_gen_service.dart  backend-proxy image provider (+ demo fallback)
├── features/
│   ├── home/                      Dictionary + Study tab shell
│   ├── dictionary/                search, "+" promote-to-card
│   ├── study/                     queue controller, flashcard flip, grade bar
│   └── editor/                    edit/categorize/delete + image fallback
├── app_services.dart             composition root (InheritedWidget)
└── main.dart
```

### Data model
The visual-anchor image is stored as a **BLOB** in SQLite (not a file path), so
it works identically offline on web and native.

### SRS
Classic SM-2 ease/interval math plus Anki-style learning steps (1m, 10m) for new
and lapsed cards. See `lib/services/srs/srs_scheduler.dart`.

### AI image generation
`DisabledImageGenProvider` is wired by default (demo mode) so the
manual-image-fallback flow works without an API key. To enable real generation,
run the proxy in [`./server`](server/README.md) and point the app at it with
`--dart-define=IMAGE_BACKEND=...` — that swaps in `ProxyImageGenProvider`
automatically (see `kImageBackendEndpoint` in `lib/app_services.dart`).

```bash
cd server && cp .env.example .env   # add OPENAI_API_KEY
npm install && npm run dev          # http://localhost:8080
# then, in the app:
flutter run -d chrome --dart-define=IMAGE_BACKEND=http://localhost:8080/image
```

The proxy keeps your OpenAI key server-side and returns raw PNG bytes that the
client reads directly into the card's visual anchor (stored as a BLOB).

## Visual-anchor image input
Each card's image can come from three sources (see
`lib/services/media/image_import_service.dart` + the editor):

1. **Generate with AI** — DALL·E via the backend proxy. Enable it by pointing
   at your endpoint at run time (no code change):
   `flutter run -d chrome --dart-define=IMAGE_BACKEND=https://api.yourapp.com/image`
   With no `IMAGE_BACKEND` set it runs in demo mode and fails on purpose so the
   manual paths are always usable. See `kImageBackendEndpoint` in
   `lib/app_services.dart`.
2. **PNG / JPG / PDF** — file picker (`file_picker`). PDFs are rasterized to a
   PNG via `printing` (first page, 150 dpi).
3. **Paste screenshot** — reads an image straight from the clipboard
   (`pasteboard`), e.g. a Print-Screen capture. Also bound to **Ctrl+V / Cmd+V**
   while the editor is open (text fields keep their own paste).

All images are stored as BLOBs in SQLite, so they stay available offline.

> File dialogs and clipboard access are OS-interactive and can't be exercised
> from a headless preview, but they are standard plugin calls and the project
> builds and analyzes cleanly with them wired in.
```
