import 'dart:convert';
import 'dart:typed_data';

/// A tiny read-only reader for SQLite database files, enough to pull rows out
/// of a table (used to read Anki decks). Pure Dart, so it works the same on
/// every platform without a native SQLite library.
///
/// Supports UTF-8 databases, table b-trees (leaf and interior pages) and
/// overflow pages. Indexes, WAL files and writing are out of scope.
class SqliteReader {
  SqliteReader(this.bytes) : _data = ByteData.sublistView(bytes) {
    if (bytes.length < 100 ||
        utf8.decode(bytes.sublist(0, 15), allowMalformed: true) != 'SQLite format 3') {
      throw const FormatException('Not an SQLite database');
    }
    final size = _data.getUint16(16);
    pageSize = size == 1 ? 65536 : size;
    _usable = pageSize - bytes[20];
  }

  final Uint8List bytes;
  final ByteData _data;
  late final int pageSize;
  late final int _usable;

  /// Table name → root page, from the schema table.
  late final Map<String, int> _tables = {
    for (final row in _rows(1))
      if (row.values.length > 3 && row.values[0] == 'table')
        '${row.values[1]}': (row.values[3] as int),
  };

  bool hasTable(String name) => _tables.containsKey(name);

  /// Every row of table [name]; an `INTEGER PRIMARY KEY` column (stored as
  /// NULL) reads as the row id.
  List<List<Object?>> table(String name) {
    final root = _tables[name];
    if (root == null) throw FormatException('No table "$name"');
    return [
      for (final row in _rows(root))
        [
          for (var i = 0; i < row.values.length; i++)
            i == 0 && row.values[0] == null ? row.rowid : row.values[i],
        ],
    ];
  }

  int _offset(int page) => (page - 1) * pageSize;

  Iterable<({int rowid, List<Object?> values})> _rows(int page) sync* {
    final start = _offset(page);
    final header = page == 1 ? start + 100 : start;
    final type = bytes[header];
    final cells = _data.getUint16(header + 3);
    final interior = type == 0x05;
    if (type != 0x05 && type != 0x0D) return; // not a table b-tree page
    final pointers = header + (interior ? 12 : 8);
    for (var i = 0; i < cells; i++) {
      var at = start + _data.getUint16(pointers + 2 * i);
      if (interior) {
        yield* _rows(_data.getUint32(at));
        continue;
      }
      final (payload, n1) = _varint(at);
      at += n1;
      final (rowid, n2) = _varint(at);
      at += n2;
      yield (rowid: rowid, values: _record(_payload(at, payload)));
    }
    if (interior) yield* _rows(_data.getUint32(header + 8));
  }

  /// The cell's full payload, following overflow pages when it is long.
  Uint8List _payload(int at, int size) {
    final maxLocal = _usable - 35;
    if (size <= maxLocal) return bytes.sublist(at, at + size);
    final minLocal = ((_usable - 12) * 32 ~/ 255) - 23;
    var local = minLocal + (size - minLocal) % (_usable - 4);
    if (local > maxLocal) local = minLocal;
    final out = BytesBuilder(copy: false)..add(bytes.sublist(at, at + local));
    var next = _data.getUint32(at + local);
    var left = size - local;
    while (next != 0 && left > 0) {
      final page = _offset(next);
      final take = left < _usable - 4 ? left : _usable - 4;
      out.add(bytes.sublist(page + 4, page + 4 + take));
      left -= take;
      next = _data.getUint32(page);
    }
    return out.toBytes();
  }

  List<Object?> _record(Uint8List p) {
    final data = ByteData.sublistView(p);
    final (headerSize, n) = _varintIn(p, 0);
    var h = n;
    var body = headerSize;
    final values = <Object?>[];
    while (h < headerSize) {
      final (serial, len) = _varintIn(p, h);
      h += len;
      switch (serial) {
        case 0:
          values.add(null);
        case 1:
          values.add(data.getInt8(body));
          body += 1;
        case 2:
          values.add(data.getInt16(body));
          body += 2;
        case 3:
          values.add((data.getInt8(body) << 16) | data.getUint16(body + 1));
          body += 3;
        case 4:
          values.add(data.getInt32(body));
          body += 4;
        case 5:
          values.add((data.getInt16(body) << 32) | data.getUint32(body + 2));
          body += 6;
        case 6:
          values.add(data.getInt64(body));
          body += 8;
        case 7:
          values.add(data.getFloat64(body));
          body += 8;
        case 8:
          values.add(0);
        case 9:
          values.add(1);
        default:
          if (serial >= 12) {
            final length = (serial - (serial.isEven ? 12 : 13)) ~/ 2;
            final slice = p.sublist(body, body + length);
            values.add(serial.isEven ? slice : utf8.decode(slice, allowMalformed: true));
            body += length;
          } else {
            values.add(null);
          }
      }
    }
    return values;
  }

  (int, int) _varint(int at) => _varintIn(bytes, at);

  /// A SQLite varint: big-endian, 7 bits per byte, the 9th byte whole.
  static (int, int) _varintIn(Uint8List b, int at) {
    var value = 0;
    for (var i = 0; i < 8; i++) {
      final byte = b[at + i];
      value = (value << 7) | (byte & 0x7F);
      if (byte & 0x80 == 0) return (value, i + 1);
    }
    return ((value << 8) | b[at + 8], 9);
  }
}
