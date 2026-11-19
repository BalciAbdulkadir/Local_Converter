import 'package:path/path.dart' as p;

/// Dosya formatlarının ait olduğu ana kategoriler.
/// Main categories that file formats belong to.
enum FormatCategory {
  image('Görsel'),
  document('Belge'),
  data('Veri'),
  audio('Ses'),
  video('Video');

  const FormatCategory(this.label);
  final String label;
}

/// Uygulamanın tanıdığı tek bir dosya formatı.
/// A single file format known to the application.
class FileFormat {
  const FileFormat(this.id, this.extensions, this.category, this.description);

  /// Kısa, büyük harfli kimlik (ör. "PNG").
  final String id;

  /// Bu formata ait uzantılar; ilki çıktı dosyalarında kullanılır.
  final List<String> extensions;
  final FormatCategory category;
  final String description;

  String get extension => extensions.first;

  @override
  String toString() => id;
}

/// Desteklenen tüm formatların kataloğu.
/// Catalogue of every supported format.
abstract final class Formats {
  // --- Görsel ---
  static const png = FileFormat('PNG', ['png'], FormatCategory.image, 'Kayıpsız, şeffaflık destekli');
  static const jpg = FileFormat('JPG', ['jpg', 'jpeg', 'jpe', 'jfif'], FormatCategory.image, 'Fotoğraflar için kayıplı sıkıştırma');
  static const webp = FileFormat('WEBP', ['webp'], FormatCategory.image, 'Web için küçük boyutlu görsel');
  static const bmp = FileFormat('BMP', ['bmp', 'dib'], FormatCategory.image, 'Sıkıştırmasız bitmap');
  static const gif = FileFormat('GIF', ['gif'], FormatCategory.image, '256 renk, animasyon destekli');
  static const tiff = FileFormat('TIFF', ['tif', 'tiff'], FormatCategory.image, 'Baskı ve arşiv için');
  static const tga = FileFormat('TGA', ['tga'], FormatCategory.image, 'Oyun ve grafik araçları');
  static const ico = FileFormat('ICO', ['ico'], FormatCategory.image, 'Windows simgesi (en fazla 256 px)');
  static const psd = FileFormat('PSD', ['psd'], FormatCategory.image, 'Photoshop belgesi (yalnızca okuma)');
  static const avif = FileFormat('AVIF', ['avif'], FormatCategory.image, 'Yeni nesil görsel (FFmpeg gerekir)');
  static const heic = FileFormat('HEIC', ['heic', 'heif'], FormatCategory.image, 'iPhone fotoğrafı (FFmpeg gerekir, yalnızca okuma)');

  // --- Belge ---
  static const pdf = FileFormat('PDF', ['pdf'], FormatCategory.document, 'Taşınabilir belge');
  static const docx = FileFormat('DOCX', ['docx'], FormatCategory.document, 'Microsoft Word belgesi');
  static const txt = FileFormat('TXT', ['txt', 'text', 'log'], FormatCategory.document, 'Düz metin');
  static const md = FileFormat('MD', ['md', 'markdown'], FormatCategory.document, 'Markdown');
  static const html = FileFormat('HTML', ['html', 'htm'], FormatCategory.document, 'Web sayfası');

  // --- Veri ---
  static const json = FileFormat('JSON', ['json'], FormatCategory.data, 'JavaScript Object Notation');
  static const yaml = FileFormat('YAML', ['yaml', 'yml'], FormatCategory.data, 'Okunabilir yapılandırma');
  static const csv = FileFormat('CSV', ['csv'], FormatCategory.data, 'Virgülle ayrılmış tablo');
  static const tsv = FileFormat('TSV', ['tsv', 'tab'], FormatCategory.data, 'Sekmeyle ayrılmış tablo');
  static const xml = FileFormat('XML', ['xml'], FormatCategory.data, 'Genişletilebilir işaretleme dili');
  static const xlsx = FileFormat('XLSX', ['xlsx'], FormatCategory.data, 'Excel çalışma kitabı');

  // --- Ses ---
  static const mp3 = FileFormat('MP3', ['mp3'], FormatCategory.audio, 'En yaygın ses formatı');
  static const wav = FileFormat('WAV', ['wav', 'wave'], FormatCategory.audio, 'Sıkıştırmasız ses');
  static const flac = FileFormat('FLAC', ['flac'], FormatCategory.audio, 'Kayıpsız sıkıştırılmış ses');
  static const ogg = FileFormat('OGG', ['ogg', 'oga'], FormatCategory.audio, 'Ogg Vorbis');
  static const m4a = FileFormat('M4A', ['m4a', 'aac'], FormatCategory.audio, 'AAC ses');
  static const opus = FileFormat('OPUS', ['opus'], FormatCategory.audio, 'Konuşma ve müzik için verimli');
  static const wma = FileFormat('WMA', ['wma'], FormatCategory.audio, 'Windows Media Audio (yalnızca okuma)');
  static const aiff = FileFormat('AIFF', ['aiff', 'aif'], FormatCategory.audio, 'Apple sıkıştırmasız ses (yalnızca okuma)');

  // --- Video ---
  static const mp4 = FileFormat('MP4', ['mp4', 'm4v'], FormatCategory.video, 'H.264 video, her yerde oynar');
  static const mkv = FileFormat('MKV', ['mkv'], FormatCategory.video, 'Matroska kapsayıcı');
  static const webm = FileFormat('WEBM', ['webm'], FormatCategory.video, 'VP9 web videosu');
  static const mov = FileFormat('MOV', ['mov', 'qt'], FormatCategory.video, 'QuickTime');
  static const avi = FileFormat('AVI', ['avi'], FormatCategory.video, 'Eski cihazlarla uyumlu');
  static const flv = FileFormat('FLV', ['flv'], FormatCategory.video, 'Flash video (yalnızca okuma)');
  static const wmv = FileFormat('WMV', ['wmv', 'asf'], FormatCategory.video, 'Windows Media Video (yalnızca okuma)');
  static const mpeg = FileFormat('MPEG', ['mpg', 'mpeg', 'ts', 'mts', 'm2ts', 'vob'], FormatCategory.video, 'MPEG akışı (yalnızca okuma)');
  static const threeGp = FileFormat('3GP', ['3gp', '3g2'], FormatCategory.video, 'Eski telefon videosu (yalnızca okuma)');

  static const List<FileFormat> all = [
    png, jpg, webp, bmp, gif, tiff, tga, ico, psd, avif, heic,
    pdf, docx, txt, md, html,
    json, yaml, csv, tsv, xml, xlsx,
    mp3, wav, flac, ogg, m4a, opus, wma, aiff,
    mp4, mkv, webm, mov, avi, flv, wmv, mpeg, threeGp,
  ];

  static final Map<String, FileFormat> _byExtension = {
    for (final f in all)
      for (final e in f.extensions) e: f,
  };

  /// Dosya yolunun uzantısından formatı bulur; tanınmıyorsa null döner.
  /// Detects the format from the file path's extension; null if unknown.
  static FileFormat? fromPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return _byExtension[ext];
  }

  static FileFormat? byId(String id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Dosya seçicide kullanılacak tüm uzantılar.
  static List<String> get allExtensions => _byExtension.keys.toList();
}
