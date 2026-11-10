import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
  String get geminiAttached =>
      _t('Gemini attached', 'Gemini ulangan', 'Gemini подключён');
  String get model => _t('Model', 'Model', 'Модель');
  String get geminiBlurb => _t(
        'Attach Gemini to auto-expand notes, generate quizzes, '
            'grade typed answers, and suggest categories.',
        'Gemini ulansa, qaydlarni to‘ldiradi, testlar tuzadi, yozilgan '
            'javoblarni baholaydi va turkumlarni taklif qiladi.',
        'Подключите Gemini, чтобы дополнять заметки, создавать тесты, '
            'проверять ответы и предлагать категории.',
      );
  String get geminiKey => _t('Gemini API key', 'Gemini API kaliti', 'API-ключ Gemini');
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
            'comments). Attach Gemini to accept any working code.',
        'Oflayn tekshiruv mos kodni talab qiladi (bo‘shliq va izohlar '
            'hisobga olinmaydi). Har qanday ishlaydigan kod qabul qilinishi '
            'uchun Gemini ulang.',
        'Офлайн-проверка требует совпадения (без учёта пробелов и '
            'комментариев). Подключите Gemini, чтобы принимался любой рабочий код.',
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
