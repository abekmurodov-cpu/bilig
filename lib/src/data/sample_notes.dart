import 'package:uuid/uuid.dart';

import '../l10n/app_strings.dart';
import '../models/knowledge_item.dart';

/// The tag on sample notes, so they can be told apart and removed.
const Set<String> sampleTags = {'sample', 'namuna', 'пример'};

typedef _Sample = (KnowledgeType, String front, String back, String category, List<String> marks);

/// A small "try it" set in the interface language: a few subjects, with
/// answers and highlights, so every practice mode (fill-in-the-blank too)
/// works right away, even without an AI.
List<KnowledgeItem> sampleNotes(AppLanguage language, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final (tag, samples) = switch (language) {
    AppLanguage.en => ('sample', _en),
    AppLanguage.uz => ('namuna', _uz),
    AppLanguage.ru => ('пример', _ru),
  };
  const uuid = Uuid();
  return [
    for (final (type, front, back, category, marks) in samples)
      KnowledgeItem(
        id: uuid.v4(),
        front: front,
        back: back,
        type: type,
        category: category,
        createdAt: at,
        dueDate: at,
        highlights: marks,
        tags: [tag],
      ),
  ];
}

const List<_Sample> _en = [
  (KnowledgeType.concept, 'Mitochondria',
      'The part of the cell that turns food into ATP, the cell’s energy.', 'Biology', ['ATP']),
  (KnowledgeType.fact, 'Photosynthesis happens in the chloroplasts.',
      'Plants use light, water and carbon dioxide to make glucose and oxygen.', 'Biology',
      ['chloroplasts', 'glucose']),
  (KnowledgeType.concept, 'Osmosis',
      'Water moving through a membrane towards the side with more dissolved substance.',
      'Biology', ['membrane']),
  (KnowledgeType.question, 'What is the largest organ of the human body?', 'The skin.',
      'Biology', []),
  (KnowledgeType.fact, 'The Amazon is the largest rainforest on Earth.',
      'It covers parts of nine countries; most of it is in Brazil.', 'Geography', ['Brazil']),
  (KnowledgeType.question, 'What is the capital of Japan?', 'Tokyo.', 'Geography', []),
  (KnowledgeType.command, 'git status',
      'Shows which files are changed, staged or not tracked yet.', 'Computers', ['staged']),
  (KnowledgeType.fact, 'HTTP status 404 means “Not Found”.',
      'Codes starting with 4 are client errors; codes starting with 5 are server errors.',
      'Computers', ['client errors', 'server errors']),
];

const List<_Sample> _uz = [
  (KnowledgeType.concept, 'Mitoxondriya',
      'Hujayraning ozuqani ATPga, ya’ni hujayra energiyasiga aylantiradigan qismi.',
      'Biologiya', ['ATP']),
  (KnowledgeType.fact, 'Fotosintez xloroplastlarda sodir bo‘ladi.',
      'O‘simliklar yorug‘lik, suv va karbonat angidriddan glyukoza va kislorod hosil qiladi.',
      'Biologiya', ['xloroplastlarda', 'glyukoza']),
  (KnowledgeType.concept, 'Osmos',
      'Suvning membrana orqali erigan modda ko‘proq bo‘lgan tomonga o‘tishi.', 'Biologiya',
      ['membrana']),
  (KnowledgeType.question, 'Inson tanasidagi eng katta organ qaysi?', 'Teri.', 'Biologiya', []),
  (KnowledgeType.fact, 'Amudaryo Orol dengiziga quyiladi.',
      'U Pomir tog‘laridan boshlanib, O‘zbekiston va Turkmaniston chegarasi bo‘ylab oqadi.',
      'Geografiya', ['Orol dengiziga', 'Pomir']),
  (KnowledgeType.question, 'Yaponiyaning poytaxti qaysi shahar?', 'Tokio.', 'Geografiya', []),
  (KnowledgeType.command, 'git status',
      'Qaysi fayllar o‘zgargani, tayyorlangani yoki hali kuzatilmayotganini ko‘rsatadi.',
      'Kompyuter', ['o‘zgargani']),
  (KnowledgeType.fact, 'HTTP 404 holati “Topilmadi” degani.',
      '4 bilan boshlanadigan kodlar mijoz xatolari, 5 bilan boshlanadiganlari server xatolari.',
      'Kompyuter', ['mijoz xatolari', 'server xatolari']),
];

const List<_Sample> _ru = [
  (KnowledgeType.concept, 'Митохондрии',
      'Часть клетки, которая превращает пищу в АТФ — энергию клетки.', 'Биология', ['АТФ']),
  (KnowledgeType.fact, 'Фотосинтез происходит в хлоропластах.',
      'Растения из света, воды и углекислого газа получают глюкозу и кислород.', 'Биология',
      ['хлоропластах', 'глюкозу']),
  (KnowledgeType.concept, 'Осмос',
      'Движение воды через мембрану в сторону, где больше растворённого вещества.',
      'Биология', ['мембрану']),
  (KnowledgeType.question, 'Какой самый большой орган человеческого тела?', 'Кожа.',
      'Биология', []),
  (KnowledgeType.fact, 'Амазонка — крупнейший тропический лес на Земле.',
      'Он занимает части девяти стран, большая часть — в Бразилии.', 'География',
      ['Бразилии']),
  (KnowledgeType.question, 'Какая столица Японии?', 'Токио.', 'География', []),
  (KnowledgeType.command, 'git status',
      'Показывает изменённые, подготовленные и ещё не отслеживаемые файлы.', 'Компьютеры',
      ['подготовленные']),
  (KnowledgeType.fact, 'HTTP-статус 404 означает «Не найдено».',
      'Коды на 4 — ошибки клиента, коды на 5 — ошибки сервера.', 'Компьютеры',
      ['ошибки клиента', 'ошибки сервера']),
];
