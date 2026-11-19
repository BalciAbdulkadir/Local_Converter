import 'conversion.dart';
import 'converters/data_converter.dart';
import 'converters/document_converter.dart';
import 'converters/image_converter.dart';
import 'converters/media_converter.dart';
import 'converters/pdf_converter.dart';
import 'formats.dart';
import 'tools.dart';

/// Hangi giriş → çıkış dönüşümünü hangi dönüştürücünün yapacağını belirler.
class ConverterRegistry {
  ConverterRegistry([List<Converter>? converters])
      : converters = converters ??
            [ImageConverter(), PdfConverter(), DocumentConverter(), DataConverter(), MediaConverter()];

  final List<Converter> converters;

  /// Formatı okuyabilen bir dönüştürücü var mı (araçlar kurulu olmasa bile)?
  bool isKnownInput(FileFormat format) => converters.any((c) => c.inputFormats.contains(format));

  Converter? find(FileFormat input, FileFormat output, ExternalTools tools) {
    for (final c in converters) {
      if (c.supports(input, output, tools)) return c;
    }
    return null;
  }

  Set<FileFormat> outputsFor(FileFormat input, ExternalTools tools) => {
        for (final c in converters)
          if (c.inputFormats.contains(input)) ...c.outputFormatsFor(input, tools),
      };

  /// Seçili dosyaların hepsinin dönüştürülebildiği hedef formatlar (katalog sırasıyla).
  List<FileFormat> commonOutputs(Iterable<FileFormat> inputs, ExternalTools tools) {
    Set<FileFormat>? common;
    for (final f in inputs.toSet()) {
      final outs = outputsFor(f, tools);
      common = common == null ? outs : common.intersection(outs);
    }
    if (common == null) return [];
    return Formats.all.where(common.contains).toList();
  }

  /// Dosyaların tek bir PDF'te birleştirilip birleştirilemeyeceği.
  bool canMergeToPdf(Iterable<FileFormat> inputs, ExternalTools tools) =>
      inputs.length > 1 && inputs.every((f) => PdfMerger.canMerge(f) && outputsFor(f, tools).contains(Formats.pdf));
}
