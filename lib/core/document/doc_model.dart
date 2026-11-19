/// Belge dönüşümlerinde kullanılan ara model.
///
/// Her okuyucu (TXT, MD, HTML, DOCX, PDF) belgeyi bu modele çevirir; her yazıcı
/// (TXT, MD, HTML, DOCX, PDF) bu modelden çıktı üretir. Böylece N okuyucu ve M
/// yazıcı ile N×M dönüşüm elde edilir.
library;

/// Satır içi metin parçası (kalın, italik, kod, bağlantı).
class Inline {
  const Inline(this.text, {this.bold = false, this.italic = false, this.code = false, this.link});

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? link;

  Inline copyWith({String? text, bool? bold, bool? italic, bool? code, String? link}) => Inline(
        text ?? this.text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        code: code ?? this.code,
        link: link ?? this.link,
      );
}

sealed class Block {
  const Block();
}

class HeadingBlock extends Block {
  const HeadingBlock(this.level, this.spans);
  final int level; // 1-6
  final List<Inline> spans;
}

class ParagraphBlock extends Block {
  const ParagraphBlock(this.spans);
  final List<Inline> spans;
}

class ListItem {
  const ListItem(this.spans, {this.level = 0});
  final List<Inline> spans;
  final int level;
}

class ListBlock extends Block {
  const ListBlock(this.items, {this.ordered = false});
  final List<ListItem> items;
  final bool ordered;
}

class CodeBlock extends Block {
  const CodeBlock(this.text);
  final String text;
}

class QuoteBlock extends Block {
  const QuoteBlock(this.spans);
  final List<Inline> spans;
}

class RuleBlock extends Block {
  const RuleBlock();
}

/// Tablo; ilk satır başlık kabul edilir.
class TableBlock extends Block {
  const TableBlock(this.rows);
  final List<List<String>> rows;
}

class Doc {
  const Doc(this.blocks, {this.title});
  final List<Block> blocks;
  final String? title;
}

String spansToPlain(List<Inline> spans) => spans.map((s) => s.text).join();

/// Ardışık aynı biçimli parçaları birleştirir ve boşlukları sadeleştirir.
List<Inline> normalizeSpans(List<Inline> spans) {
  final out = <Inline>[];
  for (final s in spans) {
    if (s.text.isEmpty) continue;
    if (out.isNotEmpty) {
      final last = out.last;
      if (last.bold == s.bold && last.italic == s.italic && last.code == s.code && last.link == s.link) {
        out[out.length - 1] = last.copyWith(text: last.text + s.text);
        continue;
      }
    }
    out.add(s);
  }
  return out;
}
