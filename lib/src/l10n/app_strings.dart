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
  String searchNotesCount(int n) => _t('Search $n notes', '$n ta qaydni qidirish',
      'Поиск по заметкам: $n');
  String foundNotes(int n) =>
      _t(n == 1 ? '1 note' : '$n notes', '$n ta qayd', 'Найдено заметок: $n');
  String get allCategories =>
      _t('All categories', 'Barcha turkumlar', 'Все категории');
  String categoriesChosen(int n) =>
      _t('$n categories', '$n ta turkum', 'Категорий: $n');
  String get showAll => _t('Show all', 'Hammasini ko‘rsatish', 'Показать все');
  String startCards(int n) => _t(n == 1 ? 'Start · 1 card' : 'Start · $n cards',
      'Boshlash · $n ta karta', 'Начать · карточек: $n');
  String get pickACategory =>
      _t('Pick a category', 'Turkumni tanlang', 'Выберите категорию');
  String get sessionDone =>
      _t('Session complete', 'Mashg‘ulot tugadi', 'Занятие завершено');
  String get greatSession => _t('Great work!', 'Ajoyib!', 'Отлично!');
  String practiseMissed(int n) => _t(
      n == 1 ? 'Practise the 1 you missed' : 'Practise the $n you missed',
      'Xato qilingan $n tasini qayta mashq qilish',
      'Повторить ошибки: $n');
  String get statusNew => _t('New', 'Yangi', 'Новая');
  String get statusDue => _t('Due now', 'Takrorlash vaqti', 'Пора повторить');
  String nextIn(int days) => days <= 0
      ? _t('Later today', 'Bugun', 'Сегодня')
      : _t('In $days d', '$days kundan keyin', 'Через $days дн.');
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
  String get topic => _t('Topic', 'Mavzu', 'Тема');
  String get organizeNotes => _t('Organize notes', 'Qaydlarni saralash', 'Разложить заметки');
  String get organizeHint => _t(
      'Long-press notes to select them, then tap Move to… and pick a topic.',
      'Qaydlarni tanlash uchun uzoq bosing, so‘ng “Ko‘chirish…” ni bosib mavzuni tanlang.',
      'Долгим нажатием выделите заметки, затем нажмите «Переместить…» и выберите тему.');
  String get topics => _t('Topics', 'Mavzular', 'Темы');
  String get practiseAll => _t('Practise all', 'Hammasini mashq qilish', 'Повторить всё');
  String get practiseTopic =>
      _t('Practise this topic', 'Shu mavzuni mashq qilish', 'Повторить тему');
  String get seeNotes => _t('See notes', 'Qaydlarni ko‘rish', 'Заметки');
  String get addNote => _t('Add a note', 'Qayd qo‘shish', 'Добавить заметку');
  String get renameCategory =>
      _t('Rename category', 'Turkum nomini o‘zgartirish', 'Переименовать категорию');
  String get renameTopic =>
      _t('Rename topic', 'Mavzu nomini o‘zgartirish', 'Переименовать тему');
  String get emptyRemovesTopic => _t('Leave empty to remove the topic',
      'Mavzuni olib tashlash uchun bo‘sh qoldiring', 'Оставьте пустым, чтобы убрать тему');
  String get noTopics => _t(
      'No topics yet. Add one when writing a note, or select notes in Notes '
          '(long-press) and move them to a topic.',
      'Hali mavzular yo‘q. Qayd yozayotganda mavzu qo‘shing yoki Qaydlar '
          'bo‘limida qaydlarni tanlab (uzoq bosing) mavzuga o‘tkazing.',
      'Тем пока нет. Добавьте тему при создании заметки или выделите заметки '
          '(долгое нажатие) и перенесите их в тему.');
  String withoutTopic(int n) =>
      _t('$n without a topic', '$n tasi mavzusiz', 'Без темы: $n');
  String notesCount(int n) => _t(n == 1 ? '1 note' : '$n notes', '$n ta qayd', 'Заметок: $n');
  String get tryAgain => _t('Try again', 'Qayta urinish', 'Повторить попытку');
  String selectedCount(int n) => _t('$n selected', '$n ta tanlandi', 'Выбрано: $n');
  String get moveTo => _t('Move to…', 'Ko‘chirish…', 'Переместить…');
  String get move => _t('Move', 'Ko‘chirish', 'Переместить');
  String moveNotes(int n) => _t(n == 1 ? 'Move 1 note' : 'Move $n notes',
      '$n ta qaydni ko‘chirish', 'Переместить заметки: $n');
  String deleteNotes(int n) => _t(n == 1 ? 'Delete 1 note?' : 'Delete $n notes?',
      '$n ta qayd o‘chirilsinmi?', 'Удалить заметки: $n?');
  String get dailyGoal => _t('Daily goal', 'Kunlik maqsad', 'Цель на день');
  String reviewsADay(int n) =>
      _t('$n reviews a day', 'Kuniga $n ta takrorlash', '$n повторений в день');
  String goalLeft(int n) => _t('$n more to reach today’s goal',
      'Bugungi maqsadgacha yana $n ta', 'До цели на сегодня: $n');
  String get goalReached => _t('Today’s goal reached!', 'Bugungi maqsadga erishildi!',
      'Цель на сегодня выполнена!');
  String get recentlyAdded => _t('Recently added', 'Yaqinda qo‘shilgan', 'Недавно добавленные');
  String get strugglingWith => _t('Struggling with', 'Qiyin bo‘layotganlar', 'Даются с трудом');
  String get seeAll => _t('See all', 'Hammasi', 'Все');
  String get practiseThese => _t('Practise these', 'Shularni mashq qilish', 'Повторить их');
  String get undo => _t('Undo', 'Bekor qilish', 'Отменить');
  String notesDeleted(int n) => _t(n == 1 ? 'Note deleted' : '$n notes deleted',
      n == 1 ? 'Qayd o‘chirildi' : '$n ta qayd o‘chirildi', 'Удалено заметок: $n');
  String get autoBackups =>
      _t('Automatic backups', 'Avtomatik zaxiralar', 'Автоматические копии');
  String get autoBackupsSubtitle => _t('A copy every week, the last 4 kept. Tap to restore.',
      'Har hafta nusxa, oxirgi 4 tasi saqlanadi. Tiklash uchun bosing.',
      'Копия раз в неделю, хранятся 4 последние. Нажмите, чтобы восстановить.');
  String get autoBackupsBlurb => _t(
      'Restoring keeps your newer changes: a note is only replaced by an older copy if it was deleted.',
      'Tiklashda yangi o‘zgarishlaringiz saqlanadi: faqat o‘chirilgan qaydlar qaytariladi.',
      'При восстановлении новые изменения сохраняются: возвращаются только удалённые заметки.');
  String get noAutoBackups => _t('No automatic backup yet — the first is made on the next start.',
      'Hali avtomatik zaxira yo‘q — birinchisi keyingi ishga tushirishda yaratiladi.',
      'Автоматических копий пока нет — первая появится при следующем запуске.');
  String get aiActivity => _t('AI activity', 'AI faoliyati', 'Журнал ИИ');
  String get aiActivitySubtitle => _t('Recent requests: which AI answered and why one failed',
      'So‘nggi so‘rovlar: qaysi AI javob berdi va nima uchun xato bo‘ldi',
      'Последние запросы: какой ИИ ответил и почему была ошибка');
  String get aiActivityEmpty => _t('No AI requests yet.', 'Hali AI so‘rovlari yo‘q.',
      'Запросов к ИИ пока не было.');
  String aiTask(String task) => switch (task) {
        'expandNote' => _t('Write an answer', 'Javob yozish', 'Написать ответ'),
        'generateQuiz' || 'generateQuizzes' =>
          _t('Write questions', 'Savollar tuzish', 'Составить вопросы'),
        'gradeAnswer' => _t('Check an answer', 'Javobni tekshirish', 'Проверить ответ'),
        'gradeCode' => _t('Check code', 'Kodni tekshirish', 'Проверить код'),
        'suggestCategory' => _t('Suggest a category', 'Turkum taklifi', 'Предложить категорию'),
        'explainMistake' => _t('Why was I wrong?', 'Nega xato?', 'Почему неверно?'),
        'notesFromImage' => _t('Photo to notes', 'Rasmdan qaydlar', 'Заметки с фото'),
        'notesFromText' => _t('Split text into notes', 'Matnni qaydlarga bo‘lish', 'Разбить текст'),
        'transcribe' => _t('Voice to text', 'Ovozdan matnga', 'Голос в текст'),
        'suggestHighlights' => _t('Suggest key ideas', 'Asosiy g‘oyalar taklifi', 'Ключевые идеи'),
        _ => task,
      };
  String get fmtBold => _t('Bold', 'Qalin', 'Жирный');
  String get fmtItalic => _t('Italic', 'Kursiv', 'Курсив');
  String get fmtHeading => _t('Heading', 'Sarlavha', 'Заголовок');
  String get fmtBullets => _t('List', 'Ro‘yxat', 'Список');
  String get fmtNumbers => _t('Numbered list', 'Raqamli ro‘yxat', 'Нумерованный список');
  String get fmtCode => _t('Code', 'Kod', 'Код');
  String get fmtCodeBlock => _t('Code block', 'Kod bloki', 'Блок кода');
  String get fmtFormula => _t('Formula', 'Formula', 'Формула');
  String get fmtFormulaBlock => _t('Formula on its own line', 'Alohida qatordagi formula',
      'Формула отдельной строкой');
  String get formulaHelp => _t('Formula examples', 'Formula namunalari', 'Примеры формул');
  String get formulaHelpBlurb => _t(
      'Formulas are written in LaTeX between \$ signs. Tap one to insert it.',
      'Formulalar \$ belgilari orasida LaTeX tilida yoziladi. Qo‘shish uchun bosing.',
      'Формулы пишутся на LaTeX между знаками \$. Нажмите, чтобы вставить.');
  String get preview => _t('Preview', 'Ko‘rinishi', 'Просмотр');
  String get previewEmpty => _t('Nothing to show yet.', 'Hali ko‘rsatadigan narsa yo‘q.',
      'Пока нечего показать.');
  String get readAsPage => _t('Read as a page', 'Sahifa ko‘rinishida', 'Читать страницей');
  String get exportMarkdown =>
      _t('Export as Markdown', 'Markdown sifatida saqlash', 'Экспорт в Markdown');
  String get otherNotes => _t('Other notes', 'Boshqa qaydlar', 'Другие заметки');
  String get paperOverline => _t('MY NOTES', 'MENING QAYDLARIM', 'МОИ ЗАМЕТКИ');
  String get paperEmpty => _t('No notes here yet.', 'Bu yerda hali qayd yo‘q.', 'Здесь пока нет заметок.');
  String get contents => _t('Contents', 'Mundarija', 'Содержание');
  String get dropToAdd => _t('Drop to add notes', 'Qayd qo‘shish uchun tashlang',
      'Отпустите, чтобы добавить заметки');
  String get dropKinds => _t('Photos, text or Markdown, Anki decks, .bilig files',
      'Rasmlar, matn yoki Markdown, Anki to‘plamlari, .bilig fayllari',
      'Фото, текст или Markdown, колоды Anki, файлы .bilig');
  String get pickANote => _t('Pick a note to see it here', 'Bu yerda ko‘rish uchun qaydni tanlang',
      'Выберите заметку, чтобы открыть её здесь');
  String get allTopics => _t('All topics', 'Barcha mavzular', 'Все темы');
  String get topicOptional =>
      _t('Topic (optional)', 'Mavzu (ixtiyoriy)', 'Тема (необязательно)');
  String get topicNeedsCategory => _t('Choose a category first',
      'Avval turkumni tanlang', 'Сначала выберите категорию');
  String get topicHint => _t('A part of the course, e.g. Cells',
      'Kursning bir qismi, masalan: Hujayra', 'Часть курса, например: Клетка');
  String get topicPickHint => _t('Pick a topic or type a new one',
      'Mavzuni tanlang yoki yangisini yozing', 'Выберите тему или введите новую');
  String get newTopic => _t('New topic', 'Yangi mavzu', 'Новая тема');
  String get chooseTopic => _t('Choose a topic', 'Mavzuni tanlash', 'Выбрать тему');
  String get categoryHint => _t('e.g. Biology, History, Linux',
      'masalan: Biologiya, Tarix, Linux', 'например: Биология, История, Linux');
  String get categoryPickHint => _t('Pick one or type a new name',
      'Tanlang yoki yangi nom yozing', 'Выберите или введите новое название');
  String get newCategory =>
      _t('New category', 'Yangi turkum', 'Новая категория');
  String get chooseCategory =>
      _t('Choose a category', 'Turkumni tanlash', 'Выбрать категорию');
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

  String get clozeSelfCheck => _t(
        'Fill in the blank in your head, then reveal the answer and grade yourself.',
        'Bo‘sh joyni xayolan to‘ldiring, so‘ng javobni ochib, o‘zingizni baholang.',
        'Заполните пропуск в уме, затем откройте ответ и оцените себя.',
      );

  // --- More attractive -------------------------------------------------------
  String learnedOf(int n, int total) =>
      _t('$n/$total learned', '$n/$total o‘zlashtirildi', 'выучено $n/$total');
  String get progress => _t('Progress', 'Natijalar', 'Прогресс');
  String dayStreak(int n) => _t(n == 1 ? 'day in a row' : 'days in a row',
      'kun ketma-ket', _ruPlural(n, 'день подряд', 'дня подряд', 'дней подряд'));
  String get bestStreak => _t('best streak', 'eng uzun seriya', 'лучшая серия');
  String get rememberNow => _t('you’d remember right now', 'hozir eslay olasiz',
      'вспомните прямо сейчас');
  String get learned => _t('learned', 'o‘zlashtirilgan', 'выучено');
  String get learning => _t('learning', 'o‘rganilmoqda', 'изучается');
  String get newNotes => _t('new', 'yangi', 'новые');
  String get activity => _t('Study days', 'O‘qigan kunlar', 'Дни занятий');
  String get recallByWeek =>
      _t('Correct answers by week', 'Haftalik to‘g‘ri javoblar', 'Верные ответы по неделям');
  String get recallByWeekBlurb => _t('Share of reviews you got right.',
      'Takrorlashlardagi to‘g‘ri javoblar ulushi.', 'Доля повторений с верным ответом.');
  String get comingUp => _t('Reviews coming up', 'Kelgusi takrorlashlar', 'Предстоящие повторения');
  String reviewsCount(int n) => _t(n == 1 ? '1 review' : '$n reviews', '$n ta takrorlash',
      '$n ${_ruPlural(n, 'повторение', 'повторения', 'повторений')}');
  String get less => _t('less', 'kam', 'меньше');
  String get more => _t('more', 'ko‘p', 'больше');
  String get noReviewsYet => _t('No reviews yet. Your weeks will show here.',
      'Hali takrorlash yo‘q. Haftalaringiz shu yerda ko‘rinadi.',
      'Повторений пока нет. Здесь появятся ваши недели.');
  String get today => _t('Today', 'Bugun', 'Сегодня');
  String addSharedTitle(String name) =>
      _t('Add “$name”?', '“$name” qo‘shilsinmi?', 'Добавить «$name»?');
  String addSharedBody(int n) => _t(
        'A classmate shared $n notes. They’ll be added as new notes; ones you already have are skipped.',
        'Kursdoshingiz $n ta qayd ulashdi. Ular yangi qayd sifatida qo‘shiladi; sizda borlari o‘tkazib yuboriladi.',
        'Однокурсник поделился заметками: $n. Они добавятся как новые; уже имеющиеся будут пропущены.',
      );
  String get addNotes => _t('Add notes', 'Qo‘shish', 'Добавить');
  String get shareCategory =>
      _t('Share with classmates', 'Kursdoshlarga ulashish', 'Поделиться с однокурсниками');
  String get shareAsFile => _t('Save or send as a file', 'Fayl sifatida saqlash yoki yuborish',
      'Сохранить или отправить файлом');
  String get shareAsFileBlurb => _t(
        'A .bilig file without your progress. Classmates open it in Bilig.',
        'Natijalaringizsiz .bilig fayl. Kursdoshlar uni Bilig’da ochadi.',
        'Файл .bilig без вашего прогресса. Однокурсники откроют его в Bilig.',
      );
  String get sendToTelegram => _t('Send to my Telegram', 'Telegramimga yuborish',
      'Отправить в мой Telegram');
  String get sendToTelegramBlurb => _t(
        'Posted to your Bilig chat, ready to forward to classmates.',
        'Bilig chatingizga yuboriladi, kursdoshlarga uzatish uchun tayyor.',
        'Придёт в ваш чат Bilig — останется переслать однокурсникам.',
      );
  String sentToTelegram(String name) => _t('“$name” is in your Telegram chat. Forward it to classmates.',
      '“$name” Telegram chatingizda. Uni kursdoshlarga uzating.',
      '«$name» в вашем чате Telegram. Перешлите его однокурсникам.');
  String shareCaption(String name, int n) => _t(
        '📚 $name · $n notes for Bilig. Open it in Bilig (Settings → Open a .bilig file), or share it to Bilig.',
        '📚 $name · Bilig uchun $n ta qayd. Bilig’da oching (Sozlamalar → .bilig faylni ochish) yoki Bilig’ga ulashing.',
        '📚 $name · $n заметок для Bilig. Откройте в Bilig (Настройки → Открыть файл .bilig) или поделитесь им в Bilig.',
      );
  String get widgetDue => _t('to review', 'ta takrorlash', 'к повторению');
  String get garden => _t('Your garden', 'Bog‘ingiz', 'Ваш сад');

  // --- Easier to use --------------------------------------------------------
  String get undoGrade => _t('Undo last grade', 'Oxirgi bahoni bekor qilish',
      'Отменить последнюю оценку');
  String get swipeHint => _t('Swipe ← Again · Good →', 'Suring: ← Yana · Yaxshi →',
      'Смахните: ← Снова · Хорошо →');
  String get keyboardHint => _t('Space flip · 1–4 grade · ←/→ browse · ⌘Z undo',
      'Probel — aylantirish · 1–4 — baho · ←/→ — varaqlash · ⌘Z — bekor qilish',
      'Пробел — перевернуть · 1–4 — оценка · ←/→ — листать · ⌘Z — отменить');

  String get searchNotes => _t('Search notes', 'Qaydlarni qidirish', 'Поиск заметок');
  String get clear => _t('Clear', 'Tozalash', 'Очистить');
  String noResults(String q) => q.isEmpty
      ? _t('No notes with these tags.', 'Bu teglar bilan qayd yo‘q.', 'Нет заметок с этими тегами.')
      : _t('Nothing found for “$q”.', '“$q” bo‘yicha hech narsa topilmadi.',
          'По запросу «$q» ничего не найдено.');
  String get tagsField => _t('Tags (optional, comma-separated)',
      'Teglar (ixtiyoriy, vergul bilan)', 'Теги (необязательно, через запятую)');
  String get tagsHint => _t('e.g. exam1, hard, week3', 'masalan: imtihon1, qiyin, 3-hafta',
      'например: экзамен1, сложно, неделя3');

  String get skip => _t('Skip', 'O‘tkazib yuborish', 'Пропустить');
  String get tour1Title => _t('Notes that quiz you back', 'Sizni sinaydigan qaydlar',
      'Заметки, которые вас проверяют');
  String get tour1Body => _t(
        'Write down anything worth remembering: type it, say it, snap a photo of a page, or paste a whole lecture and let it split into notes.',
        'Eslab qolishga arziydigan hamma narsani yozing: tering, ayting, sahifani suratga oling yoki butun ma’ruzani joylab, qaydlarga bo‘ling.',
        'Записывайте всё, что стоит запомнить: напечатайте, продиктуйте, сфотографируйте страницу или вставьте целую лекцию и разбейте её на заметки.',
      );
  String get tour2Title => _t('Questions written for you', 'Savollar siz uchun yoziladi',
      'Вопросы пишутся за вас');
  String get tour2Body => _t(
        'Mark the key ideas with the marker. An AI of your choice (Gemini is free) turns each note into quiz questions; without one, highlights become fill-in-the-blank cards.',
        'Asosiy fikrlarni marker bilan belgilang. O‘zingiz tanlagan AI (Gemini bepul) har bir qaydni test savollariga aylantiradi; AIsiz belgilar bo‘sh joyni to‘ldirish kartalariga aylanadi.',
        'Отмечайте главное маркером. Выбранный вами ИИ (Gemini бесплатен) превращает каждую заметку в вопросы; без ИИ выделенное станет карточками с пропусками.',
      );
  String get tour3Title => _t('A few minutes a day', 'Kuniga bir necha daqiqa',
      'Несколько минут в день');
  String get tour3Body => _t(
        'Bilig asks each note again just before you’d forget it. Review a little every day and watch your knowledge grow into a tree.',
        'Bilig har bir qaydni unutishingizdan sal oldin yana so‘raydi. Har kuni oz-ozdan takrorlang va bilimingiz daraxtdek o‘sishini kuzating.',
        'Bilig спрашивает каждую заметку снова незадолго до того, как вы бы её забыли. Повторяйте понемногу каждый день и смотрите, как знания растут в дерево.',
      );
  String get trySamples => _t('Try it with sample notes', 'Namuna qaydlar bilan sinab ko‘rish',
      'Попробовать на примерах');
  String get startEmpty => _t('Start with my own notes', 'O‘z qaydlarim bilan boshlash',
      'Начать со своих заметок');

  String get yourNotes => _t('Your notes', 'Qaydlaringiz', 'Ваши заметки');
  String get exportBackup =>
      _t('Save a backup', 'Zaxira nusxa saqlash', 'Сохранить резервную копию');
  String get exportBackupBlurb => _t('All notes, images and progress in one .bilig file.',
      'Barcha qaydlar, rasmlar va natijalar bitta .bilig faylda.',
      'Все заметки, изображения и прогресс в одном файле .bilig.');
  String get restoreBackup =>
      _t('Open a .bilig file', '.bilig faylni ochish', 'Открыть файл .bilig');
  String get restoreBackupBlurb => _t(
        'Restore a backup or add a category a classmate shared.',
        'Zaxira nusxani tiklang yoki kursdoshingiz ulashgan turkumni qo‘shing.',
        'Восстановить копию или добавить категорию, которой поделился однокурсник.',
      );
  String get importAnki =>
      _t('Import from Anki or Quizlet', 'Anki yoki Quizletdan import', 'Импорт из Anki или Quizlet');
  String get importAnkiBlurb => _t('Anki decks (.apkg) or exported text (.txt, .csv).',
      'Anki to‘plamlari (.apkg) yoki eksport qilingan matn (.txt, .csv).',
      'Колоды Anki (.apkg) или экспортированный текст (.txt, .csv).');
  String get importTitle => _t('Import', 'Import', 'Импорт');
  String get removeSamples =>
      _t('Remove the sample notes', 'Namuna qaydlarni o‘chirish', 'Удалить примеры');
  String samplesRemoved(int n) => _t('Removed $n sample notes.',
      '$n ta namuna qayd o‘chirildi.', 'Удалено примеров: $n.');
  String backupSaved(int n) => _t('Backup saved: $n notes.',
      'Zaxira saqlandi: $n ta qayd.', 'Копия сохранена: $n заметок.');
  String imported(int added, int updated) => _t(
        'Added $added notes${updated > 0 ? ', updated $updated' : ''}.',
        '$added ta qayd qo‘shildi${updated > 0 ? ', $updated tasi yangilandi' : ''}.',
        'Добавлено: $added${updated > 0 ? ', обновлено: $updated' : ''}.',
      );
  String get nothingToImport => _t('No notes found in that file.',
      'Bu faylda qayd topilmadi.', 'В этом файле нет заметок.');
  String fileFailed(Object e) => _t('Couldn’t read or save the file: $e',
      'Faylni o‘qib yoki saqlab bo‘lmadi: $e', 'Не удалось прочитать или сохранить файл: $e');
  String get selectAll => _t('Select all', 'Hammasini tanlash', 'Выбрать все');
  String get selectNone => _t('Select none', 'Hech birini', 'Снять все');
  String get categoryForMissing => _t('Category for notes without a deck (optional)',
      'To‘plamsiz qaydlar uchun turkum (ixtiyoriy)', 'Категория для заметок без колоды (необязательно)');

  // --- Reviewing better ----------------------------------------------------
  String get partlyRight => _t('Partly right', 'Qisman to‘g‘ri', 'Частично верно');
  String get allCaughtUp => _t('All caught up', 'Hammasi takrorlangan', 'Всё повторено');
  String get practiseAhead => _t('Nothing due. Quick 5 practises what’s coming next.',
      'Takrorlash yo‘q. «Tezkor 5» keyingi qaydlarni mashq qildiradi.',
      'Повторять нечего. «Быстрые 5» потренируют то, что на очереди.');
  String dueToday(int n) => _t('$n due', '$n ta takrorlash', 'К повторению: $n');
  String aboutMinutes(int n) =>
      _t('about $n min', 'taxminan $n daqiqa', 'примерно $n мин');
  String get quickFive => _t('Quick 5', 'Tezkor 5', 'Быстрые 5');
  String examIn(String category, int days) => switch (days) {
        0 => _t('$category exam today', '$category imtihoni bugun',
            'Экзамен по $category сегодня'),
        1 => _t('$category exam tomorrow', '$category imtihoni ertaga',
            'Экзамен по $category завтра'),
        _ => _t('$category exam in $days days', '$category imtihoniga $days kun',
            'Экзамен по $category через $days ${_ruPlural(days, 'день', 'дня', 'дней')}'),
      };
  String examReady(int ready, int total) => _t('$ready of $total notes known',
      '$total ta qayddan $ready tasi o‘zlashtirilgan', 'Выучено $ready из $total');
  String get study => _t('Study', 'O‘qish', 'Учить');
  String get examMode => _t('Exam date', 'Imtihon sanasi', 'Дата экзамена');
  String get examBlurb => _t(
        'Until the exam, this category’s reviews come a bit sooner and always before the day, so everything gets a last look.',
        'Imtihongacha bu turkum takrorlari biroz tezroq va doim imtihondan oldin keladi, shunda hammasi oxirgi marta ko‘rib chiqiladi.',
        'До экзамена повторения этой категории приходят чуть чаще и всегда до его дня, чтобы всё успеть освежить.',
      );
  String get pickExamDate => _t('Pick the date', 'Sanani tanlang', 'Выберите дату');
  String get removeExam => _t('Remove exam', 'Imtihonni olib tashlash', 'Убрать экзамен');
  String get examNeedsCategory => _t('Give your notes a category first.',
      'Avval qaydlaringizga turkum bering.', 'Сначала задайте заметкам категорию.');
  String get whyWrong =>
      _t('Why was I wrong?', 'Nega xato qildim?', 'Почему я ошибся?');

  // --- Faster capture: photo, paste & split, voice, sharing -------------
  String get photoToNotes => _t('Photo → notes', 'Rasmdan qaydlar', 'Фото → заметки');
  String get pasteAndSplit =>
      _t('Paste & split', 'Joylash va bo‘lish', 'Вставить и разбить');
  String get pasteHere => _t(
        'Paste lecture notes, a summary or a list. Each line like “Term — meaning” or “Question? Answer” becomes a note.',
        'Ma’ruza konspekti, xulosa yoki ro‘yxatni joylang. “Atama — ma’nosi” yoki “Savol? Javob” ko‘rinishidagi har bir qator qaydga aylanadi.',
        'Вставьте конспект, краткое содержание или список. Каждая строка вида «Термин — значение» или «Вопрос? Ответ» станет заметкой.',
      );
  String get pasteFromClipboard => _t('Paste', 'Joylash', 'Вставить');
  String get makeNotesAi =>
      _t('Make notes with AI', 'AI bilan qaydlar yaratish', 'Сделать заметки с ИИ');
  String get splitByLines => _t('Split by lines (no AI)',
      'Qatorlarga bo‘lish (AIsiz)', 'Разбить по строкам (без ИИ)');
  String get choosePhoto => _t('Choose a photo', 'Rasm tanlash', 'Выбрать фото');
  String get anotherPhoto => _t('Another photo', 'Boshqa rasm', 'Другое фото');
  String get readingPhoto =>
      _t('Reading the photo…', 'Rasm o‘qilmoqda…', 'Читаю фото…');
  String get makingNotes =>
      _t('Making notes…', 'Qaydlar tayyorlanmoqda…', 'Готовлю заметки…');
  String get needVisionAi => _t(
        'To read photos, connect an AI that sees images (Gemini, ChatGPT, Claude, Groq…) in Settings.',
        'Rasmlarni o‘qish uchun Sozlamalarda rasmni ko‘ra oladigan AI ulang (Gemini, ChatGPT, Claude, Groq…).',
        'Чтобы читать фото, подключите в настройках ИИ, который видит изображения (Gemini, ChatGPT, Claude, Groq…).',
      );
  String notesFound(int n) => _t(
        '$n ${n == 1 ? 'note' : 'notes'} found. Untick any you don’t want; tap one to edit it.',
        '$n ta qayd topildi. Keraksizlaridan belgini olib tashlang; tahrirlash uchun bosing.',
        'Найдено заметок: $n. Снимите галочку с ненужных; нажмите, чтобы изменить.',
      );
  String get noNotesFound => _t('No notes found in it. Try another photo or text.',
      'Undan qayd topilmadi. Boshqa rasm yoki matn bilan urinib ko‘ring.',
      'Заметок не найдено. Попробуйте другое фото или текст.');
  String get categoryForAll => _t('Category for all (optional)',
      'Hammasi uchun turkum (ixtiyoriy)', 'Категория для всех (необязательно)');
  String saveNotes(int n) => _t(n == 1 ? 'Save 1 note' : 'Save $n notes',
      '$n ta qaydni saqlash', 'Сохранить: $n');
  String savedNotes(int n) => _t(n == 1 ? 'Saved 1 note.' : 'Saved $n notes.',
      '$n ta qayd saqlandi.', 'Сохранено заметок: $n.');
  String get startOver => _t('Start over', 'Qaytadan', 'Заново');
  String get speak => _t('Speak', 'Gapirish', 'Сказать');
  String get voiceDevice => _t('This device', 'Qurilma', 'Устройство');
  String get voiceAi => _t('AI (better for Uzbek)', 'AI (o‘zbekchaga yaxshi)',
      'ИИ (лучше для узбекского)');
  String get voiceLanguage => _t('Language', 'Til', 'Язык');
  String get tapToSpeak =>
      _t('Tap the mic and speak', 'Mikrofonni bosing va gapiring', 'Нажмите на микрофон и говорите');
  String get listening => _t('Listening…', 'Tinglanmoqda…', 'Слушаю…');
  String recordingFor(int s) {
    final time = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return _t('Recording… $time  ·  tap to stop',
        'Yozilmoqda… $time  ·  to‘xtatish uchun bosing',
        'Запись… $time  ·  нажмите, чтобы остановить');
  }
  String get writingItDown =>
      _t('Writing it down…', 'Matnga aylantirilmoqda…', 'Записываю текстом…');
  String get voiceTextHint => _t('What you say appears here. You can fix it before inserting.',
      'Aytganlaringiz shu yerda chiqadi. Qo‘shishdan oldin tuzatishingiz mumkin.',
      'Сказанное появится здесь. Можно поправить перед вставкой.');
  String get insertText => _t('Insert', 'Qo‘shish', 'Вставить');
  String get speechUnavailable => _t(
        'Speech recognition isn’t available here, or permission was refused.',
        'Bu yerda nutqni aniqlash mavjud emas yoki ruxsat berilmagan.',
        'Распознавание речи здесь недоступно или не разрешено.',
      );
  String get tryAiVoice => _t('Try “AI” instead.', '“AI”ni sinab ko‘ring.',
      'Попробуйте «ИИ».');
  String get micDenied => _t(
        'Bilig can’t use the microphone. Allow it in your system’s privacy settings.',
        'Bilig mikrofondan foydalana olmaydi. Tizimning maxfiylik sozlamalarida ruxsat bering.',
        'Bilig не может использовать микрофон. Разрешите это в настройках конфиденциальности.',
      );
  String get nothingHeard => _t('Nothing was heard. Try again.',
      'Hech narsa eshitilmadi. Yana urinib ko‘ring.', 'Ничего не услышано. Попробуйте ещё раз.');

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
  String get suggestKeyIdeas =>
      _t('Suggest key ideas', 'Asosiy fikrlarni taklif qilish', 'Предложить главное');
  String keyIdeasSuggested(int n) => _t(
        'Marked $n suggested key ${n == 1 ? 'idea' : 'ideas'}. Tap any to remove it, then press Done.',
        '$n ta taklif qilingan asosiy fikr belgilandi. Keraksizini bosib olib tashlang, so‘ng «Tayyor»ni bosing.',
        'Отмечено предложенного: $n. Нажмите на лишнее, чтобы убрать, затем «Готово».',
      );
  String get noNewKeyIdeas => _t('The AI found no new key ideas to mark.',
      'AI belgilash uchun yangi asosiy fikr topmadi.',
      'ИИ не нашёл нового главного для выделения.');
  String get captureMarkerHint => _t(
        'Mark key ideas: select words, then choose Highlight. Questions will focus on them.',
        'Asosiy fikrlarni belgilang: so‘zlarni tanlang va «Belgilash»ni bosing. Savollar ularga qaratiladi.',
        'Отметьте главное: выделите слова и выберите «Выделить». Вопросы будут о них.',
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
  String get textBlanksSubtitle => _t(
        'Type the missing words. Small typos are fine.',
        'Tushib qolgan so‘zlarni yozing. Kichik xatolar hisobga olinmaydi.',
        'Впишите пропущенные слова. Мелкие опечатки не страшны.',
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
        PracticeMethod.flashcard => _t('Flip, recall, grade yourself.',
            'Aylantiring, eslang, o‘zingizni baholang.', 'Переверните, вспомните, оцените себя.'),
        PracticeMethod.multipleChoice => _t('Pick the right answer.',
            'To‘g‘ri javobni tanlang.', 'Выберите правильный ответ.'),
        PracticeMethod.typeAnswer => _t('Type it; checked by match or AI.',
            'Yozing; moslik yoki AI tekshiradi.', 'Введите; проверка совпадением или ИИ.'),
        PracticeMethod.fillBlank => _t('Type the missing key words.',
            'Tushib qolgan asosiy so‘zlarni yozing.', 'Впишите пропущенные ключевые слова.'),
        PracticeMethod.codeSnippet => _t('Rewrite the snippet from memory.',
            'Kodni xotiradan qayta yozing.', 'Напишите фрагмент по памяти.'),
        PracticeMethod.reorder => _t('Put the shuffled lines in order.',
            'Aralash qatorlarni tartiblang.', 'Расставьте строки по порядку.'),
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
