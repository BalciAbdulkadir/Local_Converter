import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/conversion.dart';
import '../core/formats.dart';
import '../state/converter_controller.dart';
import 'ui_helpers.dart';

/// Sağ panel: hedef format, duruma göre değişen ayarlar, çıktı klasörü ve başlat düğmesi.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.controller});

  final ConverterController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TargetPicker(controller: c),
                if (c.target != null) ...[
                  const SizedBox(height: 8),
                  _OptionsSection(controller: c),
                ],
                const SizedBox(height: 8),
                _OutputSection(controller: c),
              ],
            ),
          ),
        ),
        _ActionBar(controller: c),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.icon = Icons.info_outline, this.warning = false});
  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = warning ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: warning ? scheme.errorContainer.withValues(alpha: 0.35) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: warning ? scheme.onErrorContainer : color, height: 1.4))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({required this.controller});
  final ConverterController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[const _SectionTitle('Hedef format')];

    if (c.missingFfmpeg) {
      children.add(const _Hint(
        'Ses, video ve AVIF/HEIC dosyaları için FFmpeg gerekiyor. ffmpeg.exe dosyasını uygulama '
        'klasörüne koyun ya da FFmpeg\'i kurup PATH\'e ekleyin, ardından uygulamayı yeniden başlatın.',
        icon: Icons.warning_amber_rounded,
        warning: true,
      ));
    }

    if (c.files.isEmpty) {
      children.add(const _Hint('Dönüştürmek istediğiniz dosyaları ekleyin; uygun hedef formatlar burada listelenir.'));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }

    final targets = c.availableTargets;
    if (targets.isEmpty) {
      children.add(_Hint(
        c.inputCategories.length > 1
            ? 'Seçili dosyalar farklı türlerde (${c.inputCategories.map((e) => e.label.toLowerCase()).join(', ')}) '
                've hepsine uygun ortak bir hedef format yok. Aynı türdeki dosyaları birlikte dönüştürün.'
            : 'Bu dosyalar için kullanılabilir bir hedef format yok.',
        icon: Icons.block,
      ));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }

    final byCategory = <FormatCategory, List<FileFormat>>{};
    for (final t in targets) {
      (byCategory[t.category] ??= []).add(t);
    }
    for (final entry in byCategory.entries) {
      final color = colorForCategory(entry.key, scheme);
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Row(children: [
          Icon(iconForCategory(entry.key), size: 16, color: color),
          const SizedBox(width: 6),
          Text(entry.key.label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ));
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in entry.value)
              Tooltip(
                message: f.description,
                waitDuration: const Duration(milliseconds: 500),
                child: ChoiceChip(
                  label: Text(f.id),
                  selected: c.target == f,
                  onSelected: c.isRunning ? null : (sel) => c.setTarget(sel ? f : null),
                ),
              ),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

// ---------------------------------------------------------------------------

class _OptionsSection extends StatelessWidget {
  const _OptionsSection({required this.controller});
  final ConverterController controller;

  static const _resizePresets = [null, 3840, 2560, 1920, 1280, 1024, 800, 512, 256];
  static const _bitrates = [96, 128, 160, 192, 256, 320];
  static const _videoHeights = [null, 2160, 1440, 1080, 720, 480, 360];

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final o = c.options;
    final t = c.target!;
    final inputs = c.inputFormats;
    final enabled = !c.isRunning;
    void set(ConversionOptions n) => c.updateOptions(n);

    final hasImageInputs = inputs.any((f) => f.category == FormatCategory.image);
    final hasPdfInputs = inputs.contains(Formats.pdf);
    final hasVideoInputs = inputs.any((f) => f.category == FormatCategory.video);
    final widgets = <Widget>[];

    // --- Görsel kalitesi ---
    if (t == Formats.jpg || t == Formats.webp || t == Formats.avif) {
      widgets.add(_LabeledSlider(
        label: 'Kalite',
        value: o.imageQuality,
        min: 10,
        max: 100,
        enabled: enabled,
        onChanged: (v) => set(o.copyWith(imageQuality: v)),
      ));
    }

    // --- Boyutlandırma ---
    if (t.category == FormatCategory.image || (t == Formats.pdf && hasImageInputs)) {
      final current = o.maxWidth;
      widgets.add(_Dropdown<int?>(
        label: 'En uzun kenar',
        value: _resizePresets.contains(current) ? current : null,
        items: {for (final v in _resizePresets) v: v == null ? 'Orijinal boyut' : '$v px'},
        enabled: enabled,
        onChanged: (v) => set(o.copyWith(maxWidth: () => v, maxHeight: () => v)),
      ));
    }

    // --- PDF → görsel çözünürlüğü ---
    if (hasPdfInputs && t.category == FormatCategory.image) {
      widgets.add(_Dropdown<int>(
        label: 'PDF çözünürlüğü',
        value: o.pdfRenderDpi,
        items: const {72: '72 DPI (ekran)', 150: '150 DPI (standart)', 300: '300 DPI (baskı)'},
        enabled: enabled,
        onChanged: (v) => set(o.copyWith(pdfRenderDpi: v)),
      ));
      widgets.add(const _Hint('Her PDF sayfası ayrı bir görsel dosyası olarak kaydedilir.'));
    }

    // --- PDF çıktısı ---
    if (t == Formats.pdf) {
      final onlyImages = inputs.every((f) => f.category == FormatCategory.image);
      // Sayfa boyutu yalnızca yeni PDF sayfası üretilen girişler (görsel/belge) için anlamlı.
      if (inputs.any((f) => f != Formats.pdf)) {
        widgets.add(_Dropdown<PdfPageSize>(
          label: 'Sayfa boyutu',
          value: !onlyImages && o.pdfPageSize == PdfPageSize.fit ? PdfPageSize.a4 : o.pdfPageSize,
          items: {
            for (final s in PdfPageSize.values)
              if (onlyImages || s != PdfPageSize.fit) s: s.label,
          },
          enabled: enabled,
          onChanged: (v) => set(o.copyWith(pdfPageSize: v)),
        ));
      }
      if (c.canMerge) {
        widgets.add(SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tek PDF dosyasında birleştir'),
          subtitle: Text(c.willMerge
              ? 'Liste sırasıyla tek dosya oluşturulur'
              : 'Her dosya için ayrı PDF oluşturulur'),
          value: o.mergeIntoSinglePdf,
          onChanged: enabled ? (v) => set(o.copyWith(mergeIntoSinglePdf: v)) : null,
        ));
      }
      if (hasPdfInputs && !c.willMerge) {
        widgets.add(const _Hint('PDF dosyaları sayfalara bölünür: her sayfa ayrı bir PDF olur.'));
      }
    }

    // --- Belgeye çeviri uyarısı ---
    if (hasPdfInputs && t.category == FormatCategory.document && t != Formats.pdf) {
      widgets.add(const _Hint(
        'PDF\'ten yalnızca metin aktarılır; görseller ve sayfa düzeni korunmaz. '
        'Taranmış (resim) PDF\'lerde metin bulunmaz.',
      ));
    }

    // --- CSV ---
    if (t == Formats.csv) {
      widgets.add(SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Ayraç olarak noktalı virgül (;)'),
        subtitle: const Text('Türkçe Excel CSV\'yi bu şekilde açar'),
        value: o.csvSemicolon,
        onChanged: enabled ? (v) => set(o.copyWith(csvSemicolon: v)) : null,
      ));
    }

    // --- Ses bit hızı ---
    const lossless = {Formats.wav, Formats.flac, Formats.gif};
    if ((t.category == FormatCategory.audio || t.category == FormatCategory.video || (t == Formats.gif && hasVideoInputs)) &&
        !lossless.contains(t)) {
      widgets.add(_Dropdown<int>(
        label: 'Ses bit hızı',
        value: o.audioBitrateKbps,
        items: {for (final b in _bitrates) b: '$b kbps'},
        enabled: enabled,
        onChanged: (v) => set(o.copyWith(audioBitrateKbps: v)),
      ));
    }

    // --- Video ---
    final videoTarget = t.category == FormatCategory.video;
    final gifFromVideo = t == Formats.gif && hasVideoInputs;
    if (videoTarget) {
      widgets.add(_Dropdown<VideoQuality>(
        label: 'Video kalitesi',
        value: o.videoQuality,
        items: {for (final q in VideoQuality.values) q: q.label},
        enabled: enabled,
        onChanged: (v) => set(o.copyWith(videoQuality: v)),
      ));
    }
    if (videoTarget || gifFromVideo) {
      widgets.add(_Dropdown<int?>(
        label: 'En fazla yükseklik',
        value: o.videoMaxHeight,
        items: {for (final h in _videoHeights) h: h == null ? (gifFromVideo ? 'Otomatik (480 px genişlik)' : 'Orijinal') : '${h}p'},
        enabled: enabled,
        onChanged: (v) => set(o.copyWith(videoMaxHeight: () => v)),
      ));
    }
    if (gifFromVideo) {
      widgets.add(_Dropdown<int>(
        label: 'Kare hızı',
        value: o.gifFps,
        items: const {8: '8 fps', 10: '10 fps', 12: '12 fps', 15: '15 fps', 20: '20 fps', 24: '24 fps'},
        enabled: enabled,
        onChanged: (v) => set(o.copyWith(gifFps: v)),
      ));
      widgets.add(const _Hint('Uzun videolardan GIF çok büyük dosyalar oluşturabilir.'));
    }

    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const _SectionTitle('Ayarlar'), ...widgets],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ 5,
            label: '$value',
            onChanged: enabled ? (v) => onChanged(v.round()) : null,
          ),
        ),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final bool enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(
          child: DropdownButtonFormField<T>(
            initialValue: items.containsKey(value) ? value : items.keys.first,
            key: ValueKey('$label-$value'),
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
            ],
            onChanged: enabled ? (v) => onChanged(v as T) : null,
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

class _OutputSection extends StatelessWidget {
  const _OutputSection({required this.controller});
  final ConverterController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final dir = c.options.outputDirectory;
    final enabled = !c.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Çıktı konumu'),
        RadioGroup<bool>(
          groupValue: dir == null,
          onChanged: (sameFolder) async {
            if (!enabled || sameFolder == null) return;
            if (sameFolder) {
              c.updateOptions(c.options.copyWith(outputDirectory: () => null));
            } else {
              await _pickFolder(c);
            }
          },
          child: Column(children: [
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: true,
              enabled: enabled,
              title: const Text('Kaynak dosyanın yanına'),
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: false,
              enabled: enabled,
              title: const Text('Seçtiğim klasöre'),
              subtitle: dir == null
                  ? null
                  : Text(dir, maxLines: 2, overflow: TextOverflow.ellipsis),
              secondary: dir == null
                  ? null
                  : IconButton(
                      tooltip: 'Klasörü değiştir',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: enabled ? () => _pickFolder(c) : null,
                    ),
            ),
          ]),
        ),
        Text(
          'Aynı adda dosya varsa üzerine yazılmaz; "ad (1)" gibi yeni bir ad verilir.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _pickFolder(ConverterController c) async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Çıktı klasörünü seçin');
    if (path != null) c.updateOptions(c.options.copyWith(outputDirectory: () => path));
  }
}

// ---------------------------------------------------------------------------

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});
  final ConverterController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final outputs = c.allOutputs;

    String? summary;
    if (c.isRunning) {
      final finished = c.doneCount + c.failedCount + c.cancelledCount;
      summary = '${c.willMerge ? 'Birleştiriliyor' : '$finished / ${c.files.length} tamamlandı'} · %${(c.overallProgress * 100).round()}';
    } else if (c.hasResults) {
      final parts = [
        if (c.doneCount > 0) '${c.doneCount} başarılı',
        if (c.failedCount > 0) '${c.failedCount} hatalı',
        if (c.cancelledCount > 0) '${c.cancelledCount} iptal',
      ];
      summary = parts.join(' · ');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary != null) ...[
            Row(children: [
              Expanded(
                child: Text(summary, style: TextStyle(color: c.failedCount > 0 && !c.isRunning ? scheme.error : null)),
              ),
              if (!c.isRunning && outputs.isNotEmpty)
                TextButton.icon(
                  onPressed: () => revealInExplorer(outputs.first),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(p.basename(p.dirname(outputs.first)), overflow: TextOverflow.ellipsis),
                ),
            ]),
            const SizedBox(height: 8),
            if (c.isRunning) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: c.overallProgress, minHeight: 6),
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (c.isRunning)
            OutlinedButton.icon(
              onPressed: c.cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('İptal Et'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            )
          else
            FilledButton.icon(
              onPressed: c.canStart ? c.start : null,
              icon: const Icon(Icons.bolt),
              label: Text(c.target == null
                  ? 'Hedef format seçin'
                  : c.willMerge
                      ? '${c.files.length} dosyayı PDF\'te birleştir'
                      : '${c.files.length} dosyayı ${c.target!.id} formatına dönüştür'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
        ],
      ),
    );
  }
}
