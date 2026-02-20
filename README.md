# Local Format Converter 🔄

A privacy-first, offline desktop file converter built with Flutter. This application allows you to convert image files (PNG, JPG) and generate PDFs entirely on your local machine. It features a custom sub-process integration for high-performance WebP conversion.

**[⏬ Download the latest Windows (.exe) Release here!](../../releases/latest)**

## 🚀 Features

* **Complete Privacy:** 100% local processing. No internet connection required, no cloud uploads.
* **Drag & Drop Interface:** Modern and intuitive desktop UI for quick file loading.
* **Hybrid Processing Architecture:** * Uses Dart's native `Isolate` for background PNG/JPG processing.
  * Uses a custom hidden sub-process (`Process.run`) to execute Google's `cwebp.exe` for lightning-fast WebP encoding without relying on heavy C++ wrappers or freezing the UI.
* **Supported Formats:** Converts between PNG, JPG, and WEBP, plus PDF document generation.
* **Smart Filtering:** Built-in extension validation and error handling for unsupported files.

## 🛠️ Tech Stack & Architecture

* **Framework:** Flutter (Dart) - Optimized for Windows Desktop.
* **Core Packages:**
  * `image`: For low-level pixel manipulation and Isolate-based encoding.
  * `pdf`: For generating PDF documents from images.
  * `desktop_drop` & `file_picker`: For seamless desktop file management.
* **Architecture:** UI and Business Logic are strictly separated. The `ConverterService` acts as the core engine routing tasks to either Dart Isolates or System Processes based on the target format.

## ⚙️ Building from Source

If you want to compile the project yourself instead of downloading the pre-built release:

### Prerequisites
* Flutter SDK (3.x.x or higher)
* Visual Studio 2022 with "Desktop development with C++" workload (for Windows compilation)

📝 Roadmap

    [x] Windows Desktop MVP

    [x] Background processing with Isolates

    [x] Sub-process execution for WebP (cwebp.exe)

    [x] Add real-time batch progress bar UI

    [x] Add custom error handling and extension filtering

    [ ] Extend to Android with platform-specific native codecs

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
