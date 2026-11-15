import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin client over the Telegram Bot API used as a cloud store. The note
/// database is uploaded as a JSON **document** and **pinned** in a private
/// channel/chat; the pinned message is the single source of truth. A fresh
/// device reads it back via `getChat` → `pinned_message` → `getFile`.
///
/// Uploading a new document + re-pinning on every push keeps the flow uniform
/// regardless of payload size (avoiding the 4096-char text-message limit) at the
/// cost of leaving old messages behind — acceptable for a private sync channel.
class TelegramSyncService {
  TelegramSyncService({
    required this.botToken,
    required this.chatId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String botToken;
  final String chatId;
  final http.Client _client;

  static const String _fileName = 'knowledge.json';

  static final RegExp _tokenPattern = RegExp(r'\d+:[A-Za-z0-9_-]{30,}');

  /// Extracts the bare `123456:ABC…` token from whatever the user pasted — a
  /// `bot` prefix, an api.telegram.org URL, or BotFather's whole message.
  static String normalizeToken(String input) {
    final match = _tokenPattern.firstMatch(input);
    return match?.group(0) ?? input.replaceAll(RegExp(r'\s'), '');
  }

  /// Accepts `-100…` ids, `@name`, bare `name`, or `t.me/name` links.
  static String normalizeChatId(String input) {
    var id = input.trim();
    final link = RegExp(r'(?:https?://)?t(?:elegram)?\.me/([A-Za-z0-9_]+)')
        .firstMatch(id);
    if (link != null) id = link.group(1)!;
    if (RegExp(r'^-?\d+$').hasMatch(id) || id.startsWith('@')) return id;
    return '@$id';
  }

  String get _apiBase => 'https://api.telegram.org/bot$botToken';
  String get _fileBase => 'https://api.telegram.org/file/bot$botToken';

  /// Calls a Bot API method and returns its `result`, throwing on API errors.
  Future<dynamic> _call(String method, Map<String, dynamic> params) async {
    final resp = await _client.post(
      Uri.parse('$_apiBase/$method'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(params),
    );
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } on FormatException {
      throw Exception('Telegram $method failed: HTTP ${resp.statusCode}');
    }
    if (body['ok'] != true) {
      throw Exception(_explain(method, body['description'] as String?));
    }
    return body['result'];
  }

  /// Turns Telegram's terse error descriptions into actionable messages.
  static String _explain(String method, String? description) {
    final d = description ?? 'unknown error';
    if (d == 'Unauthorized') {
      return 'Telegram rejected the bot token. Copy it again from @BotFather '
          '(or /revoke and use the new one).';
    }
    if (d == 'Not Found') {
      return 'The bot token is malformed. It should look like '
          '123456789:AAH… with no "bot" prefix or extra text.';
    }
    if (d.contains('chat not found')) {
      return 'Chat not found. Add the bot to the channel as an admin, and use '
          '@channelname (public) or the -100… id (private).';
    }
    return 'Telegram $method failed: $d';
  }

  /// Validates the token and returns the bot's username (for the settings UI).
  Future<String> getMe() async {
    final result = await _call('getMe', const {}) as Map<String, dynamic>;
    return result['username'] as String? ?? 'bot';
  }

  /// Confirms the bot can see [chatId], so a bad id fails at attach time
  /// instead of on the first sync.
  Future<void> checkChat() => _call('getChat', {'chat_id': chatId});

  /// Downloads the pinned note database, or null if nothing is pinned yet.
  Future<String?> pull() async {
    final chat = await _call('getChat', {'chat_id': chatId})
        as Map<String, dynamic>;
    final pinned = chat['pinned_message'] as Map<String, dynamic>?;
    if (pinned == null) return null;

    final doc = pinned['document'] as Map<String, dynamic>?;
    if (doc == null) {
      // Legacy/inline text fallback.
      return pinned['text'] as String?;
    }
    final fileId = doc['file_id'] as String;
    final file = await _call('getFile', {'file_id': fileId})
        as Map<String, dynamic>;
    final path = file['file_path'] as String;
    final resp = await _client.get(Uri.parse('$_fileBase/$path'));
    if (resp.statusCode != 200) {
      throw Exception('Telegram file download failed: ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes);
  }

  /// Posts a file to the chat without pinning it (sync is unaffected), e.g.
  /// a shared category the student then forwards to classmates.
  Future<void> sendFile(List<int> bytes, String filename, {String? caption}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_apiBase/sendDocument'))
      ..fields['chat_id'] = chatId
      ..files.add(http.MultipartFile.fromBytes('document', bytes, filename: filename));
    if (caption != null) req.fields['caption'] = caption;
    final streamed = await _client.send(req);
    final body = jsonDecode(await streamed.stream.bytesToString()) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw Exception('Telegram sendDocument failed: ${body['description']}');
    }
  }

  /// Uploads [json] as the new pinned database document.
  Future<void> push(String json) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBase/sendDocument'),
    )
      ..fields['chat_id'] = chatId
      ..fields['disable_notification'] = 'true'
      ..files.add(http.MultipartFile.fromString(
        'document',
        json,
        filename: _fileName,
      ));

    final streamed = await _client.send(req);
    final respBody = await streamed.stream.bytesToString();
    final body = jsonDecode(respBody) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw Exception('Telegram sendDocument failed: ${body['description']}');
    }
    final message = body['result'] as Map<String, dynamic>;
    final messageId = message['message_id'];

    try {
      await _call('pinChatMessage', {
        'chat_id': chatId,
        'message_id': messageId,
        'disable_notification': true,
      });
    } catch (e) {
      // Pinning is how other devices discover the latest database; without it
      // sync can't converge. The usual cause is the bot lacking admin rights.
      if (e.toString().contains('not enough rights')) {
        throw Exception(
          'The bot must be an admin in this chat with the "Pin Messages" '
          'right. Promote it in Telegram and try again.',
        );
      }
      rethrow;
    }
  }
}
