# Local Format Converter

Privacy-first, offline desktop file converter built with Flutter. This application allows you to convert image files (PNG, JPG, BMP) and generate PDFs entirely on your local machine without sending a single byte to the cloud.

## 🚀 Features

* **Complete Privacy:** 100% local processing. No internet connection required, no cloud uploads.
* **Drag & Drop Interface:** Modern and intuitive desktop UI for quick file loading.
* **Asynchronous Processing:** Heavy image decoding/encoding operations run on background threads (`Isolates`), ensuring the UI never freezes.
* **Supported Formats:** Converts between PNG, JPG, and BMP, plus PDF document generation.

## 🛠️ Tech Stack & Architecture

* **Framework:** Flutter (Dart) - Currently optimized for Windows Desktop.
* **Core Packages:**
  * `image`: For low-level pixel manipulation and format encoding.
  * `pdf`: For generating PDF documents from images.
  * `desktop_drop` & `file_picker`: For seamless desktop file management.
* **Architecture:** UI and Business Logic are strictly separated. The `ConverterService` handles all heavy lifting via Dart's `Isolate.run()`.

## ⚙️ Getting Started

### Prerequisites
* Flutter SDK (3.x.x or higher)
* Visual Studio 2022 with "Desktop development with C++" workload (for Windows compilation)

📝 Roadmap

    [x] Windows Desktop MVP

    [x] Background processing with Isolates

    [x] Add real-time progress bar UI

    [x] Add custom error handling for unsupported file types

    [ ] Extend to Android with Scoped Storage support
