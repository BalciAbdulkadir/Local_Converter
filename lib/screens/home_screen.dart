import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/formats.dart';
import '../state/converter_controller.dart';
import '../ui/drop_zone.dart';
import '../ui/file_list.dart';
import '../ui/settings_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});

  /// Testlerde sahte araçlarla çalışmak için dışarıdan verilebilir.
  final ConverterController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ConverterController _controller = widget.controller ?? ConverterController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _addPaths(List<String> paths) {
    final result = _controller.addPaths(paths);
    final messages = <String>[];
    if (result.unsupported.isNotEmpty) {
      final names = result.unsupported.take(3).join(', ');
      final more = result.unsupported.length > 3 ? ' ve ${result.unsupported.length - 3} dosya daha' : '';
      messages.add('Desteklenmeyen dosyalar atlandı: $names$more');
    }
    if (result.duplicates > 0) messages.add('${result.duplicates} dosya zaten listede.');
    if (messages.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(messages.join('\n')), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: Formats.allExtensions,
      dialogTitle: 'Dönüştürülecek dosyaları seçin',
    );
    if (result == null) return;
    _addPaths([for (final f in result.files) if (f.path != null) f.path!]);
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Klasör seçin (alt klasörler dahil)');
    if (path != null) _addPaths([path]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final hasFiles = c.files.isNotEmpty;

        final left = Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasFiles)
                DropZone(
                  compact: true,
                  enabled: !c.isRunning,
                  onPaths: _addPaths,
                  onPickFiles: _pickFiles,
                  onPickFolder: _pickFolder,
                )
              else
                Expanded(
                  child: DropZone(
                    compact: false,
                    enabled: !c.isRunning,
                    onPaths: _addPaths,
                    onPickFiles: _pickFiles,
                    onPickFolder: _pickFolder,
                  ),
                ),
              if (hasFiles) Expanded(child: FileList(controller: c)),
            ],
          ),
        );

        // Material: paneldeki ListTile/Switch dokunma efektleri görünür olsun diye.
        final panel = Material(
          color: scheme.surfaceContainerLow,
          shape: Border(left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          child: SettingsPanel(controller: c),
        );

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 24,
            title: Row(children: [
              Icon(Icons.swap_horiz_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              const Text('Local Converter', style: TextStyle(fontWeight: FontWeight.w700)),
            ]),
            actions: [_ToolStatus(controller: c), const SizedBox(width: 16)],
          ),
          body: LayoutBuilder(builder: (context, box) {
            if (box.maxWidth >= 900) {
              return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: left),
                SizedBox(width: 380, child: panel),
              ]);
            }
            // Dar pencere: panel alta gelir.
            return Column(children: [
              Expanded(flex: 5, child: left),
              Expanded(flex: 6, child: panel),
            ]);
          }),
        );
      },
    );
  }
}

/// Üst çubukta harici araçların durumunu gösterir.
class _ToolStatus extends StatelessWidget {
  const _ToolStatus({required this.controller});
  final ConverterController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.toolsLoaded) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    Widget chip(String label, bool ok, String tooltip) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Tooltip(
            message: tooltip,
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(ok ? Icons.check_circle : Icons.cancel_outlined,
                  size: 16, color: ok ? const Color(0xFF81C784) : Theme.of(context).colorScheme.onSurfaceVariant),
              label: Text(label),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      chip(
        c.tools.hasFfmpeg ? 'FFmpeg ${c.tools.ffmpegVersion ?? ''}'.trim() : 'FFmpeg yok',
        c.tools.hasFfmpeg,
        c.tools.ffmpegPath ?? 'Ses, video ve AVIF dönüşümleri için FFmpeg gerekir.',
      ),
      chip('WebP', c.tools.hasCwebp || c.tools.hasFfmpeg, c.tools.cwebpPath ?? 'cwebp.exe bulunamadı'),
    ]);
  }
}
