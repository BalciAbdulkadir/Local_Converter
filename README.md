# Local Format Converter 🔄

A privacy-first, offline desktop file converter built with Flutter. Convert images, documents, data files, audio and video entirely on your own machine — nothing is ever uploaded.

**[⏬ Download the latest Windows (.exe) Release here!](../../releases/latest)**

## 🚀 Features

* **Complete Privacy:** 100% local processing. No internet connection required, no cloud uploads.
* **One window for everything:** Drop any mix of files or whole folders; the app only offers target formats that work for *all* selected files.
* **Batch processing:** Parallel conversion for images/documents/data, per-file progress, cancel at any time.
* **Safe output:** Existing files are never overwritten (`name (1).ext`), output can go next to the source or into a folder of your choice.
* **Turkish-friendly:** PDF output embeds Windows system fonts so `ş ğ ı İ` render correctly; CSV output can use `;` and a UTF-8 BOM for Turkish Excel.

## 📦 Supported Conversions

| Category | Reads | Writes | Options |
|---|---|---|---|
| **Images** | PNG, JPG, WEBP, BMP, GIF, TIFF, TGA, ICO, PSD, AVIF¹, HEIC¹ | PNG, JPG, WEBP², BMP, GIF, TIFF, TGA, ICO, AVIF¹, PDF | Quality, resize (longest edge), auto EXIF rotation, transparent → white for JPG |
| **Documents** | TXT, Markdown, HTML, DOCX, PDF | TXT, Markdown, HTML, DOCX, PDF | Page size (A4 / Letter) |
| **PDF tools** | PDF + images + documents | Single merged PDF, one PDF per page (split), page images (PNG/JPG/…), text | Render DPI (72 / 150 / 300) |
| **Data** | JSON, YAML, CSV, TSV, XML, XLSX | JSON, YAML, CSV, TSV, XML, XLSX, HTML table | `;` delimiter for CSV |
| **Audio**¹ | MP3, WAV, FLAC, OGG, M4A/AAC, OPUS, WMA, AIFF | MP3, WAV, FLAC, OGG, M4A, OPUS | Bitrate |
| **Video**¹ | MP4, MKV, WEBM, MOV, AVI, FLV, WMV, MPEG/TS, 3GP | MP4 (H.264), MKV, WEBM (VP9), MOV, AVI, GIF, or audio only | Quality preset, max height, GIF frame rate |

¹ Requires FFmpeg (see below). ² Uses the bundled `cwebp.exe`, falls back to FFmpeg.

Converting to the same format is allowed where it is useful — e.g. PNG → PNG to resize, MP4 → MP4 to shrink, CSV → CSV to change the delimiter, JSON → JSON to pretty-print.

Notes:
* Document conversions keep structure (headings, bold/italic, links, lists, quotes, code blocks, tables), not exact visual layout.
* PDF → text/document extracts the text layer only; scanned (image-only) PDFs have no text (no OCR).
* Nested JSON/YAML/XML is flattened to `a.b.c` columns for CSV/XLSX and restored when converting back.

## 🎬 FFmpeg

Audio, video, AVIF and HEIC need [FFmpeg](https://ffmpeg.org/download.html). The app looks for it in this order:

1. `assets/ffmpeg.exe` bundled into the build (put the file there before `flutter build`; it is git-ignored),
2. `ffmpeg.exe` next to `local_converter.exe`,
3. your system `PATH` (e.g. `winget install Gyan.FFmpeg`).

The top bar shows whether FFmpeg was found and which version.

## 🛠️ Tech Stack & Architecture

* **Framework:** Flutter (Dart), optimized for Windows desktop.
* **Core packages:** `image` (pixel work in isolates), `pdf` (PDF generation), `pdfrx` (PDFium: render, text, merge, split), `markdown` / `html` / `xml` / `yaml` / `csv` / `archive` (DOCX & XLSX are read/written directly as OOXML), `desktop_drop` & `file_picker`.

```
lib/
├── core/
│   ├── formats.dart              # Format catalogue (extensions, categories)
│   ├── conversion.dart           # Converter interface, options, cancel token, safe output paths
│   ├── converter_registry.dart   # Picks the converter for input → output, common targets
│   ├── conversion_service.dart   # Batch runner: concurrency, merge mode, error reporting
│   ├── tools.dart                # cwebp / FFmpeg discovery + FFmpeg runner with progress & cancel
│   ├── converters/               # image, document, pdf, data, media (FFmpeg)
│   ├── document/                 # Intermediate document model + readers/writers (TXT, MD, HTML, DOCX)
│   └── data/                     # JSON / YAML / CSV / XML / XLSX codecs
├── state/converter_controller.dart  # Screen state (ChangeNotifier)
├── ui/                           # Drop zone, file list, settings panel
└── screens/home_screen.dart
```

Documents are converted through a small intermediate model (headings, paragraphs, lists, tables…), so every reader works with every writer.

## ⚙️ Building from Source

### Prerequisites
* Flutter SDK 3.47 or newer (Dart 3.13+, required by `pdfrx`)
* Visual Studio 2022/2026 with the **"Desktop development with C++"** workload (MSVC, CMake tools, Windows SDK) — also needed by `pdfrx`'s native build hook, including for `flutter test`
* Windows **Developer Mode** enabled (Flutter plugins need symlinks): `start ms-settings:developers`
* Internet access on the first build (PDFium binaries are downloaded by `pdfrx`)

```bash
flutter pub get
flutter test
flutter build windows --release
```

## 📝 Roadmap

    [x] Windows Desktop MVP
    [x] Background processing with Isolates
    [x] Sub-process execution for WebP (cwebp.exe)
    [x] Real-time batch progress UI
    [x] Custom error handling and extension filtering
    [x] Documents: TXT / Markdown / HTML / DOCX / PDF
    [x] PDF tools: merge, split, PDF → images / text
    [x] Data: JSON / YAML / CSV / TSV / XML / XLSX
    [x] Audio & video via FFmpeg (progress + cancel)
    [ ] OCR for scanned PDFs
    [ ] Extend to Android with platform-specific native codecs

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
