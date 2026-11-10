import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/sync/telegram_sync_service.dart';

void main() {
  const token = '123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw';

  test('normalizeToken strips prefixes, URLs and surrounding text', () {
    expect(TelegramSyncService.normalizeToken(token), token);
    expect(TelegramSyncService.normalizeToken(' bot$token\n'), token);
    expect(
      TelegramSyncService.normalizeToken(
          'https://api.telegram.org/bot$token/getMe'),
      token,
    );
    expect(
      TelegramSyncService.normalizeToken(
          'Use this token to access the HTTP API:\n$token\nKeep it secure'),
      token,
    );
  });

  test('normalizeChatId accepts ids, handles and t.me links', () {
    expect(TelegramSyncService.normalizeChatId('-1001234567890'),
        '-1001234567890');
    expect(TelegramSyncService.normalizeChatId('@my_channel'), '@my_channel');
    expect(TelegramSyncService.normalizeChatId('my_channel'), '@my_channel');
    expect(TelegramSyncService.normalizeChatId('https://t.me/my_channel'),
        '@my_channel');
  });
}
