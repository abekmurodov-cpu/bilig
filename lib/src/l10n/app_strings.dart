import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../llm/llm_provider.dart';
import '../llm/quiz_prep.dart';
import '../models/knowledge_item.dart';
import '../practice/practice_models.dart';
import '../scheduler/spaced_repetition.dart';

/// Interface languages. Only the app's own UI is translated; notes and
/// AI-generated questions stay in whatever language they were written in.
enum AppLanguage {
  en('🇺🇸', 'English'),
  uz('🇺🇿', 'O‘zbekcha'),
  ru('🇷🇺', 'Русский');

  const AppLanguage(this.flag, this.nativeName);

  final String flag;
  final String nativeName;

  Locale get locale => Locale(name);

  static AppLanguage fromCode(String? code) => AppLanguage.values
      .firstWhere((l) => l.name == code, orElse: () => AppLanguage.en);
}

/// All UI strings, with the English / Uzbek (Latin) / Russian wording side by
/// side per key. Look up with `context.s`.
class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  static const supportedLocales = [Locale('en'), Locale('uz'), Locale('ru')];
  static const LocalizationsDelegate<AppStrings> delegate = _Delegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(AppLanguage.en);

  String _t(String en, String uz, String ru) => switch (language) {
        AppLanguage.en => en,
        AppLanguage.uz => uz,
        AppLanguage.ru => ru,
      };

  /// Russian noun form for [n]: one (1, 21…), few (2–4, 22–24…), many.
  static String _ruPlural(int n, String one, String few, String many) {
    final mod10 = n % 10, mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }

  // --- Navigation --------------------------------------------------------
  String get navHome => _t('Home', 'Bosh sahifa', 'Главная');
  String get navNotes => _t('Notes', 'Qaydlar', 'Заметки');
  String get navPractice => _t('Practice', 'Mashq', 'Практика');
  String get navSettings => _t('Settings', 'Sozlamalar', 'Настройки');

  // --- Common ------------------------------------------------------------
  String get save => _t('Save', 'Saqlash', 'Сохранить');
  String get cancel => _t('Cancel', 'Bekor qilish', 'Отмена');
  String get delete => _t('Delete', 'O‘chirish', 'Удалить');
  String get edit => _t('Edit', 'Tahrirlash', 'Редактировать');
  String get remove => _t('Remove', 'Olib tashlash', 'Убрать');
  String get back => _t('Back', 'Orqaga', 'Назад');
  String get done => _t('Done', 'Tayyor', 'Готово');
  String get attach => _t('Attach', 'Ulash', 'Подключить');
  String get detach => _t('Detach', 'Uzish', 'Отключить');
  String get prompt => _t('Prompt', 'Savol', 'Вопрос');
  String get answerDetails =>
      _t('Answer / details', 'Javob / tafsilotlar', 'Ответ / подробности');
  String get category => _t('Category', 'Turkum', 'Категория');
  String get addImage => _t('Add image', 'Rasm qo‘shish', 'Добавить изображение');
  String get replaceImage =>
      _t('Replace image', 'Rasmni almashtirish', 'Заменить изображение');
  String get camera => _t('Camera', 'Kamera', 'Камера');
  String get gallery => _t('Gallery', 'Galereya', 'Галерея');
  String get noAnswerYet => _t('No answer yet', 'Hali javob yo‘q', 'Ответа пока нет');
  String somethingWentWrong(Object e) => _t('Something went wrong:\n$e',
      'Nimadir noto‘g‘ri ketdi:\n$e', 'Что-то пошло не так:\n$e');

  // --- Home --------------------------------------------------------------
  String get capture => _t('Capture', 'Qo‘shish', 'Добавить');
  String get review => _t('Review', 'Takrorlash', 'Повторить');
  String readyToChallenge(int n) => _t(
        '$n ${n == 1 ? 'item' : 'items'} ready to challenge you',
        '$n ta qayd sizni sinashga tayyor',
        '$n ${_ruPlural(n, 'заметка', 'заметки', 'заметок')} к повторению',
      );
  String get emptyTitle => _t('Your notes will hit back.',
      'Qaydlaringiz sizni sinaydi.', 'Ваши заметки будут вас проверять.');
  String get emptyBody => _t(
        'Capture a fact, a concept, a command, or a question. '
            'The app will quiz you on it later so you never forget.',
        'Fakt, tushuncha, buyruq yoki savolni yozib qo‘ying. '
            'Ilova keyinroq sizni shu bo‘yicha sinaydi va siz hech narsani '
            'unutmaysiz.',
        'Запишите факт, понятие, команду или вопрос. '
            'Позже приложение проверит вас, чтобы вы ничего не забыли.',
      );

  // --- Notes / tree ------------------------------------------------------
  String get viewList => _t('List', 'Ro‘yxat', 'Список');
  String get viewTree => _t('Tree', 'Daraxt', 'Дерево');
  String get legendLearned => _t('Learned', 'O‘zlashtirilgan', 'Выучено');
  String get legendNeedsTraining =>
      _t('Needs training', 'Takrorlash kerak', 'Нужно повторить');
  String get noNotes => _t(
        'No notes yet. Capture some and watch them grow.',
        'Hozircha qaydlar yo‘q. Bir nechtasini yozing va ularning '
            'o‘sishini kuzating.',
        'Заметок пока нет. Добавьте несколько и смотрите, как они растут.',
      );
  String get ungrouped => _t('Ungrouped', 'Guruhsiz', 'Без категории');
  String get zoom => _t('Zoom', 'Kattalashtirish', 'Масштаб');
  String get zoomIn => _t('Zoom in', 'Yaqinlashtirish', 'Приблизить');
  String get zoomOut => _t('Zoom out', 'Uzoqlashtirish', 'Отдалить');
  String get fit => _t('Fit', 'Sig‘dirish', 'Вписать');

  // --- Capture -----------------------------------------------------------
  String get captureTitle =>
      _t('Capture knowledge', 'Bilim qo‘shish', 'Добавить знание');
  String get whatKind =>
      _t('What kind of thing is this?', 'Bu qanday ma’lumot?', 'Что это за запись?');
  String get promptHint => _t(
        'A question, a concept name, a command — what to recall',
        'Savol, tushuncha nomi, buyruq — nimani eslash kerak',
        'Вопрос, понятие, команда — что нужно вспомнить',
      );
  String get promptRequired => _t('Add something to recall',
      'Eslab qolish uchun biror narsa yozing', 'Напишите, что нужно запомнить');
  String get answerOptional => _t('Answer / details (optional)',
      'Javob / tafsilotlar (ixtiyoriy)', 'Ответ / подробности (необязательно)');
  String get answerHint => _t(
        'Leave blank if you only jotted a fragment',
        'Faqat parcha yozgan bo‘lsangiz, bo‘sh qoldiring',
        'Оставьте пустым, если записали только фрагмент',
      );
  String get generateAnswer =>
      _t('Generate answer', 'Javob yaratish', 'Сгенерировать ответ');
  String get categoryOptional =>
      _t('Category (optional)', 'Turkum (ixtiyoriy)', 'Категория (необязательно)');
  String get suggestCategory =>
      _t('Suggest category', 'Turkum taklif qilish', 'Предложить категорию');
  String couldNotGenerate(Object e) => _t('Could not generate: $e',
      'Yaratib bo‘lmadi: $e', 'Не удалось сгенерировать: $e');
  String couldNotSuggest(Object e) => _t('Could not suggest: $e',
      'Taklif qilib bo‘lmadi: $e', 'Не удалось предложить: $e');

  // --- Settings ----------------------------------------------------------
  String get appearance => _t('Appearance', 'Ko‘rinish', 'Оформление');
  String get themeSystem => _t('System', 'Tizim', 'Авто');
  String get themeLight => _t('Light', 'Yorug‘', 'Светлая');
  String get themeDark => _t('Dark', 'Qorong‘i', 'Тёмная');
  String get languageTitle => _t('Language', 'Til', 'Язык');
  String get reminders => _t('Reminders', 'Eslatmalar', 'Напоминания');
  String get dailyReminder => _t('Daily review reminder',
      'Kunlik takrorlash eslatmasi', 'Ежедневное напоминание');
  String get dailyReminderSubtitle => _t('A nudge to review your notes',
      'Qaydlarni takrorlash uchun eslatma', 'Напоминание повторить заметки');
  String get reminderTime => _t('Reminder time', 'Eslatma vaqti', 'Время напоминания');
  String get reminderBody => _t(
        'Time to review — your notes are waiting to challenge you.',
        'Takrorlash vaqti — qaydlaringiz sizni sinashga tayyor.',
        'Пора повторить — заметки ждут, чтобы проверить вас.',
      );
  String get aiProvider => _t('AI provider', 'AI provayder', 'ИИ-провайдер');
  String get model => _t('Model', 'Model', 'Модель');
  String get aiBlurb => _t(
        'Connect an AI to fill in notes, write practice questions, check typed '
            'answers and suggest categories. Use your own API key from any '
            'service below.',
        'Qaydlarni to‘ldirish, mashq savollarini tuzish, yozilgan javoblarni '
            'tekshirish va turkum taklif qilish uchun AI ulang. Quyidagi '
            'xizmatlardan istalganining o‘z API kalitingizdan foydalaning.',
        'Подключите ИИ, чтобы дополнять заметки, составлять вопросы, проверять '
            'ответы и предлагать категории. Используйте свой API-ключ любого '
            'сервиса ниже.',
      );
  String get service => _t('Service', 'Xizmat', 'Сервис');
  String get freeTier => _t('free tier', 'bepul tarif', 'бесплатный тариф');
  String get apiKey => _t('API key', 'API kalit', 'API-ключ');
  String get apiKeyOptional =>
      _t('API key (optional)', 'API kalit (ixtiyoriy)', 'API-ключ (необязательно)');
  String get serverAddress => _t('Server address', 'Server manzili', 'Адрес сервера');
  String get modelName => _t('Model name', 'Model nomi', 'Название модели');
  String detectedService(String name) => _t('Looks like a $name key',
      '$name kalitiga o‘xshaydi', 'Похоже на ключ $name');
  String ambiguousKey(String a, String b) => _t(
        'Could be $a or $b. Pick the service above.',
        '$a yoki $b bo‘lishi mumkin. Yuqoridan xizmatni tanlang.',
        'Это может быть $a или $b. Выберите сервис выше.',
      );
  String getKey(String name) =>
      _t('Get a $name key', '$name kalitini olish', 'Получить ключ $name');
  String get subscriptionNote => _t(
        'A ChatGPT Plus or Claude Pro subscription does not include an API key: '
            'API access is set up and paid for separately. Gemini, Groq and '
            'OpenRouter (free models) work without paying, within limits.',
        'ChatGPT Plus yoki Claude Pro obunasi API kalitini o‘z ichiga olmaydi: '
            'API alohida sozlanadi va alohida to‘lanadi. Gemini, Groq va '
            'OpenRouter (bepul modellar) cheklovlar doirasida tekin ishlaydi.',
        'Подписка ChatGPT Plus или Claude Pro не даёт API-ключ: доступ к API '
            'настраивается и оплачивается отдельно. Gemini, Groq и OpenRouter '
            '(бесплатные модели) работают без оплаты, в пределах лимитов.',
      );
  String get testAndConnect =>
      _t('Test & connect', 'Tekshirish va ulash', 'Проверить и подключить');
  String get testConnection =>
      _t('Test connection', 'Ulanishni tekshirish', 'Проверить подключение');
  String get testing => _t('Testing…', 'Tekshirilmoqda…', 'Проверяем…');
  String connectedTo(String name) =>
      _t('$name connected', '$name ulangan', '$name подключён');
  String get testOk =>
      _t('Works: the AI answered.', 'Ishlayapti: AI javob berdi.', 'Работает: ИИ ответил.');
  String aiFailure(LlmErrorKind kind, String message) => switch (kind) {
        LlmErrorKind.auth => _t(
            'The key was rejected. Check that you copied all of it and picked '
                'the right service.',
            'Kalit qabul qilinmadi. Uni to‘liq nusxalaganingizni va to‘g‘ri '
                'xizmatni tanlaganingizni tekshiring.',
            'Ключ отклонён. Проверьте, что он скопирован полностью и выбран '
                'правильный сервис.'),
        LlmErrorKind.quotaExhausted => _t(
            'The key works, but it has no credit or its limit is used up.',
            'Kalit ishlaydi, lekin unda mablag‘ yo‘q yoki limit tugagan.',
            'Ключ работает, но на нём нет средств или исчерпан лимит.'),
        LlmErrorKind.rateLimited => _t(
            'Too many requests right now. Try again in a minute.',
            'Hozir so‘rovlar juda ko‘p. Bir daqiqadan so‘ng qayta urining.',
            'Сейчас слишком много запросов. Попробуйте через минуту.'),
        LlmErrorKind.network => _t(
            'Couldn’t reach the service. Check your internet (or the server address).',
            'Xizmatga ulanib bo‘lmadi. Internetni (yoki server manzilini) tekshiring.',
            'Не удалось связаться с сервисом. Проверьте интернет (или адрес сервера).'),
        LlmErrorKind.badResponse || LlmErrorKind.other => message,
      };
  String get noModelFound => _t(
        'No usable model found. Type a model name.',
        'Mos model topilmadi. Model nomini yozing.',
        'Подходящая модель не найдена. Введите название модели.',
      );
  String get addBackup =>
      _t('Add a backup AI', 'Zaxira AI qo‘shish', 'Добавить резервный ИИ');
  String get backupBlurb => _t(
        'A backup AI is used automatically when the main one hits its limit '
            'or stops working.',
        'Zaxira AI asosiysi limitga yetganda yoki ishlamay qolganda '
            'avtomatik ishlatiladi.',
        'Резервный ИИ используется автоматически, когда основной упирается '
            'в лимит или перестаёт работать.',
      );
  String backupLabel(String name, String model) =>
      _t('Backup: $name · $model', 'Zaxira: $name · $model', 'Резерв: $name · $model');
  String get otherModel => _t('Other model…', 'Boshqa model…', 'Другая модель…');
  String get refreshModels => _t('Refresh model list',
      'Modellar ro‘yxatini yangilash', 'Обновить список моделей');
  String get syncTelegram =>
      _t('Sync (Telegram)', 'Sinxronlash (Telegram)', 'Синхронизация (Telegram)');
  String get telegramBlurb => _t(
        'Sync across devices via a Telegram bot. Create a bot with '
            '@BotFather, make a private channel, add the bot as an admin, '
            'and paste the token + chat id below. Note: the bot token is '
            'stored on-device.',
        'Telegram bot orqali qurilmalar o‘rtasida sinxronlash. @BotFather '
            'orqali bot yarating, yopiq kanal oching, botni administrator '
            'qiling va quyiga token hamda chat ID ni kiriting. Bot tokeni '
            'qurilmada saqlanadi.',
        'Синхронизация между устройствами через Telegram-бота. Создайте бота '
            'в @BotFather, сделайте приватный канал, добавьте бота '
            'администратором и вставьте токен и ID чата ниже. Токен бота '
            'хранится на устройстве.',
      );
  String get botToken => _t('Bot token', 'Bot tokeni', 'Токен бота');
  String get chatId => _t('Chat / channel id', 'Chat / kanal ID', 'ID чата / канала');
  String get chatIdHint => _t('e.g. @my_channel or -1001234567890',
      'masalan, @my_channel yoki -1001234567890',
      'например, @my_channel или -1001234567890');
  String connected(String? user, String chatId) {
    final who = user == null ? '' : ' · @$user';
    return _t('Connected$who\nChat $chatId', 'Ulangan$who\nChat $chatId',
        'Подключено$who\nЧат $chatId');
  }

  String get syncNow => _t('Sync now', 'Hozir sinxronlash', 'Синхронизировать');
  String get syncing => _t('Syncing…', 'Sinxronlanmoqda…', 'Синхронизация…');
  String get validatingBot =>
      _t('Validating bot…', 'Bot tekshirilmoqda…', 'Проверка бота…');
  String attachedBot(String user) =>
      _t('Attached @$user', '@$user ulandi', 'Подключён @$user');
  String couldNotAttach(String e) =>
      _t('Could not attach: $e', 'Ulab bo‘lmadi: $e', 'Не удалось подключить: $e');
  String synced(int n) => _t('Synced $n notes', '$n ta qayd sinxronlandi',
      'Синхронизировано: $n ${_ruPlural(n, 'заметка', 'заметки', 'заметок')}');
  String syncFailed(Object e) => _t('Sync failed: $e',
      'Sinxronlashda xato: $e', 'Ошибка синхронизации: $e');

  // --- Review / practice -------------------------------------------------
  String reviewProgress(int i, int n) =>
      _t('Review  $i/$n', 'Takrorlash  $i/$n', 'Повторение  $i/$n');
  String get answerLabel => _t('ANSWER', 'JAVOB', 'ОТВЕТ');
  String get noAnswerRecorded => _t('(no answer recorded yet)',
      '(javob hali yozilmagan)', '(ответ ещё не записан)');
  String get howWell => _t('How well did you recall it?',
      'Qanchalik yaxshi esladingiz?', 'Насколько хорошо вы вспомнили?');
  String get tapToFlip => _t('Tap the card to flip',
      'Aylantirish uchun kartani bosing', 'Нажмите на карточку, чтобы перевернуть');
  String get nothingDue => _t('Nothing due right now.',
      'Hozircha takrorlanadigan narsa yo‘q.', 'Сейчас нечего повторять.');
  String reviewed(int n) => _t('Reviewed $n. Nice work.',
      '$n ta takrorlandi. Barakalla!', 'Повторено: $n. Отличная работа!');
  String get badQuestion => _t('Bad question', 'Yomon savol', 'Плохой вопрос');
  String get badQuestionThanks => _t(
        'Thanks. This question won’t be asked again.',
        'Rahmat. Bu savol boshqa berilmaydi.',
        'Спасибо. Этот вопрос больше не появится.',
      );
  String get answerNotCounted => _t('Your answer to it doesn’t count.',
      'Unga bergan javobingiz hisobga olinmaydi.', 'Ваш ответ на него не засчитан.');
  String get ownQuestionSelfCheck => _t(
        'Your own question has no wrong options. Reveal the answer and grade yourself.',
        'O‘z savolingizda noto‘g‘ri variantlar yo‘q. Javobni oching va o‘zingizni baholang.',
        'У вашего вопроса нет неверных вариантов. Откройте ответ и оцените себя.',
      );

  // --- Note questions & highlights ---------------------------------------
  String questionsTitle(int n) =>
      _t('Questions ($n)', 'Savollar ($n)', 'Вопросы ($n)');
  String get noQuestionsYet => _t('No questions yet.', 'Hali savollar yo‘q.',
      'Вопросов пока нет.');
  String get aiWillWrite => _t(
        'The AI will write questions for this note shortly.',
        'AI bu qayd uchun tez orada savollar yozadi.',
        'ИИ скоро напишет вопросы к этой заметке.',
      );
  String get connectAiToGenerate => _t(
        'Connect an AI in Settings to write questions automatically.',
        'Savollarni avtomatik yozish uchun Sozlamalarda AI ulang.',
        'Подключите ИИ в настройках, чтобы вопросы писались автоматически.',
      );
  String get addOneQuestion => _t('1 question', '1 ta savol', '1 вопрос');
  String get addThreeQuestions => _t('3 questions', '3 ta savol', '3 вопроса');
  String get writeOwn => _t('Write my own', 'O‘zim yozaman', 'Написать свой');
  String get rewriteWithAi =>
      _t('Rewrite with AI', 'AI bilan qayta yozish', 'Переписать с ИИ');
  String get askedNext => _t('Asked next', 'Keyingi', 'Следующий');
  String get yourQuestion => _t('Yours', 'Sizniki', 'Ваш');
  String get questionField => _t('Question', 'Savol', 'Вопрос');
  String get correctAnswerField =>
      _t('Correct answer', 'To‘g‘ri javob', 'Правильный ответ');
  String get wrongOptionsField => _t('Wrong options (one per line)',
      'Noto‘g‘ri variantlar (har biri yangi qatorda)',
      'Неверные варианты (по одному в строке)');
  String get wrongOptionsHint => _t(
        'Optional. Without them the question is a self-check in multiple choice.',
        'Ixtiyoriy. Ularsiz test rejimida savol o‘z-o‘zini tekshirishga aylanadi.',
        'Необязательно. Без них в режиме теста вопрос станет самопроверкой.',
      );
  String questionsAdded(int n) => _t(
        n == 1 ? 'Added 1 question.' : 'Added $n questions.',
        '$n ta savol qo‘shildi.',
        'Добавлено: $n ${_ruPlural(n, 'вопрос', 'вопроса', 'вопросов')}.',
      );
  String get noNewQuestion => _t(
        'The AI didn’t come up with a new question. Try again.',
        'AI yangi savol topa olmadi. Yana urinib ko‘ring.',
        'ИИ не придумал нового вопроса. Попробуйте ещё раз.',
      );
  String get questionRemoved => _t('Question removed. The AI won’t write it again.',
      'Savol o‘chirildi. AI uni qayta yozmaydi.',
      'Вопрос удалён. ИИ больше его не напишет.');
  String get questionLimit => _t(
        'A note keeps at most ${KnowledgeItem.maxQuizzes} questions.',
        'Bitta qaydda ko‘pi bilan ${KnowledgeItem.maxQuizzes} ta savol bo‘ladi.',
        'В заметке может быть не больше ${KnowledgeItem.maxQuizzes} вопросов.',
      );
  String get marker => _t('Mark key ideas', 'Asosiy fikrlarni belgilash',
      'Отметить главное');
  String get markerHint => _t(
        'Tap the key words and ideas. Questions will focus on them.',
        'Asosiy so‘z va fikrlarni bosing. Savollar ularga qaratiladi.',
        'Нажимайте на главные слова и идеи. Вопросы будут о них.',
      );
  String get highlight => _t('Highlight', 'Belgilash', 'Выделить');
  String get removeHighlight =>
      _t('Remove highlight', 'Belgini olib tashlash', 'Снять выделение');
  String get tooManyHighlights => _t(
        'Mark only the key ideas: up to ${KnowledgeItem.maxHighlights} per note.',
        'Faqat asosiy fikrlarni belgilang: qaydga ${KnowledgeItem.maxHighlights} tagacha.',
        'Отмечайте только главное: до ${KnowledgeItem.maxHighlights} на заметку.',
      );
  String get highlightsSaved => _t(
        'Key ideas saved. The AI will rewrite its questions around them.',
        'Asosiy fikrlar saqlandi. AI savollarini ularga moslab qayta yozadi.',
        'Главное сохранено. ИИ перепишет вопросы с упором на это.',
      );

  String get preparingQuestions => _t('Preparing questions…',
      'Savollar tayyorlanmoqda…', 'Готовим вопросы…');
  String get startNow => _t('Start now', 'Hozir boshlash', 'Начать сейчас');
  String get showAnswer => _t('Show answer', 'Javobni ko‘rsatish', 'Показать ответ');
  String get noAiQuestion => _t(
        'No AI question for this note yet. Reveal the answer and grade yourself.',
        'Bu qayd uchun hali AI savoli yo‘q. Javobni oching va o‘zingizni baholang.',
        'Для этой заметки ещё нет вопроса от ИИ. Откройте ответ и оцените себя.',
      );
  String get noAnswerToCheck => _t(
        'This note has no answer to check against yet. Reveal it and grade yourself.',
        'Bu qaydda tekshirish uchun javob hali yo‘q. Oching va o‘zingizni baholang.',
        'У этой заметки пока нет ответа для проверки. Откройте её и оцените себя.',
      );
  String get checkedWithoutAi => _t(
        'Checked by text match (AI unavailable).',
        'Matn bo‘yicha tekshirildi (AI mavjud emas).',
        'Проверено по совпадению текста (ИИ недоступен).',
      );
  String aiPauseReason(AiPause p) => switch (p) {
        AiPause.rateLimited => _t('The AI is busy (too many requests).',
            'AI band (so‘rovlar juda ko‘p).', 'ИИ занят (слишком много запросов).'),
        AiPause.quotaExhausted => _t('Your daily AI limit is used up.',
            'Kunlik AI limitingiz tugadi.', 'Дневной лимит ИИ исчерпан.'),
        AiPause.auth => _t('Your AI key was rejected. Check it in Settings.',
            'AI kalitingiz qabul qilinmadi. Sozlamalarda tekshiring.',
            'Ключ ИИ отклонён. Проверьте его в настройках.'),
        AiPause.network => _t('No connection to the AI.', 'AI bilan aloqa yo‘q.',
            'Нет связи с ИИ.'),
        AiPause.error => _t('The AI is having trouble.', 'AI ishlashida muammo bor.',
            'У ИИ временные проблемы.'),
      };
  String get aiPauseFallback => _t(
        'Notes without an AI question are shown as self-check cards for now.',
        'AI savoli yo‘q qaydlar hozircha o‘z-o‘zini tekshirish kartasi sifatida ko‘rsatiladi.',
        'Заметки без вопроса от ИИ пока показываются как карточки самопроверки.',
      );
  String aiQuestionsReady(int ready, int total) => _t(
        'AI questions ready for $ready of $total notes',
        'AI savollari $total ta qayddan $ready tasi uchun tayyor',
        'Вопросы от ИИ готовы для $ready из $total '
            '${_ruPlural(total, 'заметки', 'заметок', 'заметок')}',
      );
  String get preparingInBackground => _t('Preparing in the background…',
      'Fonda tayyorlanmoqda…', 'Готовим в фоне…');
  String get prepareNow => _t('Prepare now', 'Hozir tayyorlash', 'Подготовить сейчас');
  String resumesAt(String time) =>
      _t('Retrying at $time', '$time da qayta uriniladi', 'Повтор в $time');
  String get noMatch => _t('No notes match this selection.',
      'Bu tanlovga mos qaydlar yo‘q.', 'Нет заметок для этого выбора.');
  String get method => _t('Method', 'Usul', 'Метод');
  String get codingDrills => _t('Coding drills', 'Kod mashqlari', 'Упражнения с кодом');
  String get codeNotesOnly =>
      _t('(code notes only)', '(faqat kod qaydlari)', '(только заметки с кодом)');
  String get scope => _t('Scope', 'Qamrov', 'Охват');
  String get noCategories => _t(
        'No categories yet — add categories to your notes.',
        'Hozircha turkumlar yo‘q — qaydlaringizga turkum qo‘shing.',
        'Категорий пока нет — добавьте категории к заметкам.',
      );
  String get startPractice =>
      _t('Start practice', 'Mashqni boshlash', 'Начать практику');
  String get skippedViewOnly => _t('Skipped · view only',
      'O‘tkazib yuborilgan · faqat ko‘rish', 'Пропущено · только просмотр');
  String ratedViewOnly(ReviewGrade g) => _t(
        'You rated it "${grade(g)}" · view only',
        'Bahoingiz: "${grade(g)}" · faqat ko‘rish',
        'Ваша оценка: «${grade(g)}» · только просмотр',
      );
  String get previous => _t('Previous', 'Oldingi', 'Назад');
  String get next => _t('Next', 'Keyingi', 'Далее');
  String get finish => _t('Finish', 'Yakunlash', 'Завершить');
  String get yourAnswer => _t('Your answer', 'Javobingiz', 'Ваш ответ');
  String get check => _t('Check', 'Tekshirish', 'Проверить');
  String get correct => _t('Correct', 'To‘g‘ri', 'Верно');
  String get incorrect => _t('Incorrect', 'Noto‘g‘ri', 'Неверно');
  String answerIs(String a) => _t('Answer: $a', 'Javob: $a', 'Ответ: $a');
  String get reproduceSnippet => _t('Reproduce this code snippet from memory.',
      'Bu kod parchasini xotiradan yozing.', 'Напишите этот фрагмент кода по памяти.');
  String get writeCodeHint => _t('Write your code here…  (Tab indents)',
      'Kodingizni shu yerga yozing…  (Tab — chekinish)', 'Пишите код здесь…  (Tab — отступ)');
  String get aiCheckFailed => _t(
        'AI check failed; used a whitespace-insensitive match.',
        'AI tekshiruvi ishlamadi; bo‘shliqlarsiz solishtirildi.',
        'Проверка ИИ не удалась; сравнение без учёта пробелов.',
      );
  String get offlineCheck => _t(
        'Offline check needs an equivalent match (ignoring whitespace and '
            'comments). Connect an AI to accept any working code.',
        'Oflayn tekshiruv mos kodni talab qiladi (bo‘shliq va izohlar '
            'hisobga olinmaydi). Har qanday ishlaydigan kod qabul qilinishi '
            'uchun AI ulang.',
        'Офлайн-проверка требует совпадения (без учёта пробелов и '
            'комментариев). Подключите ИИ, чтобы принимался любой рабочий код.',
      );
  String get fillBlanksTitle =>
      _t('Fill in the blanks', 'Bo‘sh joylarni to‘ldiring', 'Заполните пропуски');
  String get fillBlanksSubtitle => _t(
        'Tap each blank and type the missing token.',
        'Har bir bo‘sh joyni bosing va tushib qolgan qismni yozing.',
        'Нажмите на каждый пропуск и впишите недостающее.',
      );
  String get reorderTitle =>
      _t('Reorder the code', 'Kodni tartiblang', 'Расставьте код по порядку');
  String get reorderSubtitle => _t('Drag the lines into the correct order.',
      'Qatorlarni to‘g‘ri tartibda joylashtiring.', 'Перетащите строки в правильном порядке.');
  String get reference => _t('Reference', 'Namuna', 'Эталон');
  String scored(int c, int n) =>
      _t('Scored $c / $n', 'Natija: $c / $n', 'Результат: $c / $n');

  // --- Enum labels -------------------------------------------------------
  String noteType(KnowledgeType t) => switch (t) {
        KnowledgeType.fact => _t('Fact', 'Fakt', 'Факт'),
        KnowledgeType.concept => _t('Concept', 'Tushuncha', 'Понятие'),
        KnowledgeType.command => _t('Command', 'Buyruq', 'Команда'),
        KnowledgeType.code => _t('Code', 'Kod', 'Код'),
        KnowledgeType.question => _t('Question', 'Savol', 'Вопрос'),
      };

  String grade(ReviewGrade g) => switch (g) {
        ReviewGrade.again => _t('Again', 'Yana', 'Снова'),
        ReviewGrade.hard => _t('Hard', 'Qiyin', 'Трудно'),
        ReviewGrade.good => _t('Good', 'Yaxshi', 'Хорошо'),
        ReviewGrade.easy => _t('Easy', 'Oson', 'Легко'),
      };

  String methodLabel(PracticeMethod m) => switch (m) {
        PracticeMethod.flashcard => _t('Flashcard', 'Kartochka', 'Карточки'),
        PracticeMethod.multipleChoice =>
          _t('Multiple choice', 'Variantli test', 'Выбор ответа'),
        PracticeMethod.typeAnswer =>
          _t('Type the answer', 'Javobni yozish', 'Ввод ответа'),
        PracticeMethod.codeSnippet =>
          _t('Write the code', 'Kodni yozish', 'Написать код'),
        PracticeMethod.fillBlank =>
          _t('Fill in the blank', 'Bo‘sh joyni to‘ldirish', 'Заполнить пропуски'),
        PracticeMethod.reorder =>
          _t('Reorder the code', 'Kodni tartiblash', 'Порядок строк'),
      };

  String methodBlurb(PracticeMethod m) => switch (m) {
        PracticeMethod.flashcard => _t('Reveal the answer and grade yourself.',
            'Javobni oching va o‘zingizni baholang.', 'Откройте ответ и оцените себя.'),
        PracticeMethod.multipleChoice => _t('Pick the right answer from options.',
            'Variantlardan to‘g‘ri javobni tanlang.',
            'Выберите правильный ответ из вариантов.'),
        PracticeMethod.typeAnswer => _t('Type it; checked by match or AI.',
            'Javobni yozing; moslik yoki AI orqali tekshiriladi.',
            'Введите ответ; проверка по совпадению или ИИ.'),
        PracticeMethod.codeSnippet => _t(
            'Rewrite the snippet; graded on working syntax, not an exact match.',
            'Parchani qayta yozing; aniq moslik emas, ishlaydigan sintaksis '
                'baholanadi.',
            'Перепишите фрагмент; оценивается рабочий синтаксис, а не точное '
                'совпадение.'),
        PracticeMethod.fillBlank => _t('Fill the blanked-out tokens in the code.',
            'Koddagi yashirilgan qismlarni to‘ldiring.',
            'Заполните скрытые фрагменты кода.'),
        PracticeMethod.reorder => _t('Drag the shuffled code lines back into order.',
            'Aralashgan kod qatorlarini tartibga keltiring.',
            'Расставьте перемешанные строки кода по порядку.'),
      };

  String scopeLabel(PracticeScope s) => switch (s) {
        PracticeScope.all => _t('All notes', 'Barcha qaydlar', 'Все заметки'),
        PracticeScope.due =>
          _t('Due only', 'Faqat vaqti kelganlar', 'Только к повторению'),
        PracticeScope.weakPoints => _t('Weak points', 'Zaif joylar', 'Слабые места'),
        PracticeScope.category =>
          _t('Category cram', 'Turkum bo‘yicha', 'По категории'),
      };

  String scopeBlurb(PracticeScope s) => switch (s) {
        PracticeScope.all => _t('Every note, regardless of schedule.',
            'Jadvaldan qat’i nazar, barcha qaydlar.',
            'Все заметки, независимо от расписания.'),
        PracticeScope.due => _t(
            'Only notes the spaced-repetition scheduler says are due today.',
            'Faqat bugun takrorlash vaqti kelgan qaydlar.',
            'Только заметки, которые сегодня пора повторить.'),
        PracticeScope.weakPoints => _t(
            'Notes you last got wrong or keep forgetting.',
            'Oxirgi marta xato qilgan yoki tez-tez unutadigan qaydlaringiz.',
            'Заметки, в которых вы ошиблись или которые часто забываете.'),
        PracticeScope.category => _t('All notes in one category you choose.',
            'Siz tanlagan turkumdagi barcha qaydlar.',
            'Все заметки выбранной категории.'),
      };
}

extension AppStringsContext on BuildContext {
  AppStrings get s => AppStrings.of(this);
}

class _Delegate extends LocalizationsDelegate<AppStrings> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) =>
      AppLanguage.values.any((l) => l.name == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) => SynchronousFuture(
      AppStrings(AppLanguage.fromCode(locale.languageCode)));

  @override
  bool shouldReload(_Delegate old) => false;
}
