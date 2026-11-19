import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/conversion_service.dart';
import '../state/converter_controller.dart';
import 'ui_helpers.dart';

/// Seçili dosyaların listesi; her satırda format, boyut, durum ve çıktılar.
class FileList extends StatelessWidget {
  const FileList({super.key, required this.controller});

  final ConverterController controller;

  @override
  Widget build(BuildContext context) {
    final files = controller.files;
    final scheme = Theme.of(context).colorScheme;
    final totalSize = files.fold<int>(0, (s, f) => s + f.size);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Text('${files.length} dosya', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Text('· ${formatBytes(totalSize)}', style: TextStyle(color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (controller.doneCount > 0 && !controller.isRunning)
                TextButton.icon(
                  onPressed: controller.clearCompleted,
                  icon: const Icon(Icons.playlist_remove, size: 18),
                  label: const Text('Tamamlananları kaldır'),
                ),
              TextButton.icon(
                onPressed: controller.isRunning ? null : controller.clear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Tümünü temizle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, i) => _FileTile(
              entry: files[i],
              running: controller.isRunning,
              onRemove: () => controller.removeAt(i),
            ),
          ),
        ),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.entry, required this.running, required this.onRemove});

  final FileEntry entry;
  final bool running;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = colorForCategory(entry.format.category, scheme);
    final status = entry.status;

    final (String? statusText, Color? statusColor) = switch (status) {
      JobStatus.pending => ('Sırada', scheme.onSurfaceVariant),
      JobStatus.running => ('Dönüştürülüyor… %${(entry.progress * 100).round()}', scheme.primary),
      JobStatus.done => (
          entry.outputs.length == 1 ? '→ ${p.basename(entry.outputs.single)}' : '→ ${entry.outputs.length} dosya oluşturuldu',
          const Color(0xFF81C784),
        ),
      JobStatus.failed => (entry.error ?? 'Hata', scheme.error),
      JobStatus.cancelled => ('İptal edildi', scheme.onSurfaceVariant),
      null => (null, null),
    };

    Widget trailing;
    if (status == JobStatus.running) {
      trailing = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, value: entry.progress > 0 ? entry.progress : null),
      );
    } else if (status == JobStatus.done && entry.outputs.isNotEmpty) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        if (entry.outputs.length == 1)
          IconButton(
            tooltip: 'Aç',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: () => openWithDefaultApp(entry.outputs.single),
          ),
        IconButton(
          tooltip: 'Klasörde göster',
          icon: const Icon(Icons.folder_outlined, size: 20),
          onPressed: () => revealInExplorer(entry.outputs.first),
        ),
        if (!running)
          IconButton(tooltip: 'Listeden kaldır', icon: const Icon(Icons.close, size: 20), onPressed: onRemove),
      ]);
    } else {
      trailing = IconButton(
        tooltip: 'Listeden kaldır',
        icon: const Icon(Icons.close, size: 20),
        onPressed: running ? null : onRemove,
      );
    }

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(iconForFormat(entry.format), color: color, size: 22),
            ),
            title: Tooltip(
              message: entry.path,
              waitDuration: const Duration(milliseconds: 600),
              child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            subtitle: Row(
              children: [
                Text('${entry.format.id} · ${formatBytes(entry.size)}'),
                if (statusText != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Tooltip(
                      message: statusText,
                      waitDuration: const Duration(milliseconds: 400),
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: statusColor),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            trailing: trailing,
          ),
          if (status == JobStatus.running)
            LinearProgressIndicator(value: entry.progress > 0 ? entry.progress : null, minHeight: 2),
        ],
      ),
    );
  }
}
