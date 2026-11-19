import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

/// Dosya/klasör sürükle-bırak alanı. Dosya yokken büyük, varken ince bir şerit olur.
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.compact,
    required this.enabled,
    required this.onPaths,
    required this.onPickFiles,
    required this.onPickFolder,
  });

  final bool compact;
  final bool enabled;
  final void Function(List<String> paths) onPaths;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _dragging && widget.enabled;
    final borderColor = active ? scheme.primary : scheme.outlineVariant;

    final buttons = Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: widget.enabled ? widget.onPickFiles : null,
          icon: const Icon(Icons.add),
          label: const Text('Dosya Ekle'),
        ),
        OutlinedButton.icon(
          onPressed: widget.enabled ? widget.onPickFolder : null,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Klasör Ekle'),
        ),
      ],
    );

    final content = widget.compact
        ? Row(
            children: [
              Icon(Icons.file_download_outlined, color: active ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  active ? 'Bırakın, listeye eklensin' : 'Daha fazla dosya ya da klasör sürükleyin',
                  style: TextStyle(color: active ? scheme.primary : scheme.onSurfaceVariant),
                ),
              ),
              buttons,
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_upload_outlined, size: 64, color: active ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                active ? 'Bırakın!' : 'Dosyaları veya klasörleri buraya sürükleyin',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: active ? scheme.primary : null),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Görsel, PDF, Word, Markdown, Excel, CSV, JSON, ses ve video dosyaları desteklenir.\n'
                'Tüm işlemler bilgisayarınızda yapılır; hiçbir dosya internete gönderilmez.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 20),
              buttons,
            ],
          );

    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        widget.onPaths([for (final f in details.files) f.path]);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: widget.compact ? 12 : 24),
        decoration: BoxDecoration(
          color: active ? scheme.primary.withValues(alpha: 0.08) : scheme.surfaceContainerLow,
          border: Border.all(color: borderColor, width: active ? 2 : 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: content,
      ),
    );
  }
}
