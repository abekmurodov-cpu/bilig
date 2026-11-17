// Where the downloads live: the newest GitHub release. Each build is uploaded
// under the same file name, so these links always give the latest version.
const REPO = 'https://github.com/abekmurodov-cpu/bilig';
const LATEST = `${REPO}/releases/latest/download/`;

// ---------- Translations (English is in the page itself) ----------

const T = {
  uz: {
    'nav.how': 'Qanday ishlaydi',
    'nav.features': 'Imkoniyatlar',
    'nav.faq': 'Savollar',
    'nav.download': 'Yuklab olish',
    'hero.eyebrow': 'Bepul · Windows · Mac · Linux · Android',
    'hero.title': 'Sizdan <em>so‘rab turadigan</em> eslatmalar.',
    'hero.lead': 'O‘rganganingizni yozib qo‘ying. Bilig har bir eslatmadan savollar tuzadi va ularni aynan unutay deganingizda so‘raydi — o‘qiganingiz esda qoladi.',
    'hero.download': 'Yuklab olish',
    'hero.all': 'Barcha qurilmalar',
    'hero.fine': 'Ro‘yxatdan o‘tish shart emas. Eslatmalaringiz qurilmangizda qoladi.',
    'how.title': 'Uch qadam. Keyin hammasi o‘zi ishlaydi.',
    'how.1.t': 'Yozib qo‘ying',
    'how.1.p': 'Yozing, ayting, sahifani suratga oling yoki butun ma’ruzani tashlang — u eslatmalarga bo‘linadi.',
    'how.2.t': 'Bilig so‘raydi',
    'how.2.p': 'Kartochkalar, test, bo‘sh joyni to‘ldirish, javob yozish — hammasi o‘z so‘zlaringizdan.',
    'how.3.t': 'Esda qoladi',
    'how.3.p': 'Har bir eslatma unutishingizdan oldin qaytib keladi. Kuniga besh daqiqa — hammasi yodda.',
    'feat.title': 'Haqiqatan eslab qolmoqchi bo‘lganlar uchun.',
    'feat.trees.tag': 'Ko‘rinadigan natija',
    'feat.trees.t': 'Har bir fan daraxtga aylanadi.',
    'feat.trees.p': 'Har bir bo‘lim — daraxt, har bir eslatma — barg. O‘rgangan barglaringiz yashil, takrorlash kerak bo‘lganlari sariq bo‘ladi. Bir qarashda qayerda turganingiz ko‘rinadi.',
    'feat.paper.tag': 'Eslatma sahifasi',
    'feat.paper.t': 'Butun mavzu bitta chiroyli sahifada.',
    'feat.paper.p': 'Imtihon oldidan bo‘limni sahifa sifatida oching: mundarija, raqamlangan bo‘limlar, belgilaringiz va formulalar — xuddi kitobdagidek. Bir bosishda Markdown qilib saqlang.',
    'feat.ai.t': 'Aqlli savollar',
    'feat.ai.p': 'Sun’iy intellekt eslatmalaringizdan haqiqiy savollar tuzadi — usiz ham Bilig to‘liq ishlaydi.',
    'feat.fmt.t': 'Formulalar va kod',
    'feat.fmt.p': 'Qalin matn, ro‘yxatlar, rangli kod bloklari va x² + y² = z² kabi LaTeX formulalar.',
    'feat.dark.t': 'Yorug‘ va tungi rejim',
    'feat.dark.p': 'Imtihon oldidan yarim tunda ham ko‘zni charchatmaydi.',
    'feat.import.t': 'Eslatmalaringizni olib keling',
    'feat.import.p': 'Anki to‘plamlari, Markdown va matn fayllarini qo‘shing — yoki shunchaki oynaga tashlang.',
    'feat.lang.t': 'Uch til',
    'feat.lang.p': 'O‘zbekcha, Русский va English — ilova ham, savollar ham.',
    'feat.private.t': 'Sizniki, internetsiz',
    'feat.private.p': 'Eslatmalar qurilmangizda saqlanadi va internetsiz ishlaydi. Xohlagan paytda zaxira nusxa oling.',
    'feat.wide': 'Noutbukda eslatmalar ro‘yxati va ochiq eslatma yonma-yon turadi. Yangi eslatma — ⌘N / Ctrl+N, qidirish — ⌘F.',
    'dl.title': 'Bilig’ni yuklab oling',
    'dl.lead': 'Bepul. Qurilmangizni tanlang.',
    'dl.install': 'O‘rnatuvchi (.exe)',
    'dl.zip': 'O‘rnatmasdan (.zip)',
    'dl.dmg': 'Yuklab olish (.dmg)',
    'dl.deb': 'Debian, Ubuntu (.deb)',
    'dl.tar': 'Boshqa distributivlar (.tar.gz)',
    'dl.apk': 'Yuklab olish (.apk)',
    'dl.play': 'Google Play — tez orada',
    'dl.appstore': 'App Store — tez orada',
    'dl.help.t': 'Birinchi marta ochyapsizmi? Kompyuter bir marta so‘rashi mumkin.',
    'dl.help.win': '<b>Windows:</b> “Windows protected your PC” chiqsa, <i>More info → Run anyway</i> ni bosing.',
    'dl.help.mac': '<b>Mac:</b> Bilig’ni Applications papkasiga torting. Birinchi marta o‘ng tugma bilan bosib <i>Open</i>, so‘ng yana <i>Open</i> ni tanlang.',
    'dl.help.linux': '<b>Linux:</b> <code>sudo apt install ./Bilig-Linux-amd64.deb</code>, keyin Bilig’ni ilovalar ichidan toping.',
    'dl.help.android': '<b>Android:</b> faylni oching va so‘ralganda brauzerdan o‘rnatishga ruxsat bering.',
    'dl.older': 'Barcha versiyalar va o‘zgarishlar',
    'faq.title': 'Savollar',
    'faq.1.q': 'Bilig bepulmi?',
    'faq.1.a': 'Ha. Bu yerda ko‘rgan hamma narsangiz bepul.',
    'faq.2.q': 'Ro‘yxatdan o‘tish yoki internet kerakmi?',
    'faq.2.a': 'Yo‘q. Bilig internetsiz ishlaydi va eslatmalarni qurilmangizda saqlaydi. Internet faqat ixtiyoriy sun’iy intellekt imkoniyatlari uchun kerak.',
    'faq.3.q': 'Sun’iy intellekt qismi qanday ishlaydi?',
    'faq.3.a': 'U savollar tuzadi, sahifa suratlarini o‘qiydi va uzun matnlarni eslatmalarga bo‘ladi. Hozircha buning uchun Google Gemini yoki Groq’ning bepul kalitini Sozlamalarga bir marta qo‘yasiz; kalitsiz ham Bilig savollarni o‘zi tuzadi.',
    'faq.4.q': 'Eslatmalarni boshqa qurilmaga o‘tkaza olamanmi?',
    'faq.4.a': 'Bir qurilmada zaxira faylini saqlang va boshqasida oching. Bilig Anki to‘plamlari va Markdown fayllarini ham qabul qiladi.',
    'faq.5.q': 'Oraliqli takrorlash nima?',
    'faq.5.a': 'Ko‘p yillik tadqiqotlarga asoslangan o‘qish usuli: har bir ma’lumotni aynan unutay deganingizda takrorlaysiz, oraliqlar uzayib boradi va bilim uzoq muddatli xotiraga o‘tadi.',
    'final.t': 'O‘rganganingizni eslab qoling.',
    'final.b': 'Bilig’ni oling — bepul',
    'footer.source': 'GitHub’dagi manba kodi',
    'footer.privacy': 'Maxfiylik',
    'dl.for': 'Yuklab olish:',
  },
  ru: {
    'nav.how': 'Как это работает',
    'nav.features': 'Возможности',
    'nav.faq': 'Вопросы',
    'nav.download': 'Скачать',
    'hero.eyebrow': 'Бесплатно · Windows · Mac · Linux · Android',
    'hero.title': 'Заметки, которые <em>спрашивают</em> вас.',
    'hero.lead': 'Записывайте то, что изучаете. Bilig превращает каждую заметку в вопросы и задаёт их как раз перед тем, как вы забудете, — и выученное остаётся с вами.',
    'hero.download': 'Скачать',
    'hero.all': 'Все платформы',
    'hero.fine': 'Без регистрации. Заметки хранятся на вашем устройстве.',
    'how.title': 'Три шага. Дальше всё работает само.',
    'how.1.t': 'Запишите',
    'how.1.p': 'Напечатайте, надиктуйте, сфотографируйте страницу или вставьте целую лекцию — она разделится на заметки.',
    'how.2.t': 'Bilig спрашивает',
    'how.2.p': 'Карточки, тесты, пропуски в тексте, ответы своими словами — всё из ваших же записей.',
    'how.3.t': 'Запоминается',
    'how.3.p': 'Каждая заметка возвращается прямо перед тем, как вы её забудете. Пять минут в день — и всё свежо в памяти.',
    'feat.title': 'Для тех, кто правда хочет помнить.',
    'feat.trees.tag': 'Наглядный прогресс',
    'feat.trees.t': 'Каждый предмет вырастает в дерево.',
    'feat.trees.p': 'Каждая категория — дерево, каждая заметка — лист. Выученные листья зеленеют, а те, что пора повторить, желтеют: с одного взгляда видно, где вы сейчас.',
    'feat.paper.tag': 'Конспект',
    'feat.paper.t': 'Целая тема на одной красивой странице.',
    'feat.paper.p': 'Перед экзаменом откройте категорию как страницу: оглавление, пронумерованные разделы, ваши выделения и формулы — как в книге. Экспорт в Markdown одним нажатием.',
    'feat.ai.t': 'Умные вопросы',
    'feat.ai.p': 'ИИ составляет настоящие вопросы по вашим заметкам — но Bilig полностью работает и без него.',
    'feat.fmt.t': 'Формулы и код',
    'feat.fmt.p': 'Жирный текст, списки, цветные блоки кода и формулы LaTeX вроде x² + y² = z².',
    'feat.dark.t': 'Светлая и тёмная тема',
    'feat.dark.p': 'Бережёт глаза и в полночь перед экзаменом.',
    'feat.import.t': 'Переносите свои заметки',
    'feat.import.p': 'Импорт колод Anki, файлов Markdown и текста — или просто перетащите их в окно.',
    'feat.lang.t': 'Три языка',
    'feat.lang.p': 'O‘zbekcha, Русский и English — и приложение, и вопросы.',
    'feat.private.t': 'Ваше и без интернета',
    'feat.private.p': 'Заметки хранятся на устройстве и работают офлайн. Сохраняйте резервную копию, когда захотите.',
    'feat.wide': 'На ноутбуке список заметок и открытая заметка стоят рядом. ⌘N / Ctrl+N — новая заметка, ⌘F — поиск.',
    'dl.title': 'Скачать Bilig',
    'dl.lead': 'Бесплатно. Выберите своё устройство.',
    'dl.install': 'Установщик (.exe)',
    'dl.zip': 'Портативная версия (.zip)',
    'dl.dmg': 'Скачать (.dmg)',
    'dl.deb': 'Debian, Ubuntu (.deb)',
    'dl.tar': 'Любой дистрибутив (.tar.gz)',
    'dl.apk': 'Скачать (.apk)',
    'dl.play': 'Google Play — скоро',
    'dl.appstore': 'App Store — скоро',
    'dl.help.t': 'Открываете впервые? Компьютер может спросить один раз.',
    'dl.help.win': '<b>Windows:</b> если SmartScreen пишет «Система Windows защитила ваш компьютер», нажмите <i>Подробнее → Выполнить в любом случае</i>.',
    'dl.help.mac': '<b>Mac:</b> перетащите Bilig в «Программы». В первый раз нажмите правой кнопкой, выберите <i>Открыть</i>, затем ещё раз <i>Открыть</i>.',
    'dl.help.linux': '<b>Linux:</b> <code>sudo apt install ./Bilig-Linux-amd64.deb</code>, затем найдите Bilig среди приложений.',
    'dl.help.android': '<b>Android:</b> откройте файл и разрешите установку из браузера, когда спросят.',
    'dl.older': 'Все версии и список изменений',
    'faq.title': 'Вопросы',
    'faq.1.q': 'Bilig бесплатный?',
    'faq.1.a': 'Да. Всё, что вы здесь видите, бесплатно.',
    'faq.2.q': 'Нужна ли регистрация или интернет?',
    'faq.2.a': 'Нет. Bilig работает офлайн и хранит заметки на вашем устройстве. Интернет нужен только для необязательных функций ИИ.',
    'faq.3.q': 'Как работает ИИ?',
    'faq.3.a': 'Он составляет вопросы, читает фото страниц и делит длинные тексты на заметки. Пока для этого нужно один раз вставить в настройках бесплатный ключ Google Gemini или Groq; без ключа Bilig составляет вопросы сам.',
    'faq.4.q': 'Можно ли перенести заметки на другое устройство?',
    'faq.4.a': 'Сохраните файл резервной копии на одном устройстве и откройте на другом. Bilig также импортирует колоды Anki и файлы Markdown.',
    'faq.5.q': 'Что такое интервальное повторение?',
    'faq.5.a': 'Метод, подтверждённый десятилетиями исследований: вы повторяете каждый факт как раз тогда, когда начинаете его забывать, — промежутки растут, и знание уходит в долговременную память.',
    'final.t': 'Помните то, что изучаете.',
    'final.b': 'Скачать Bilig бесплатно',
    'footer.source': 'Исходный код на GitHub',
    'footer.privacy': 'Конфиденциальность',
    'dl.for': 'Скачать для',
  },
};

const english = {};
document.querySelectorAll('[data-i18n]').forEach((el) => { english[el.dataset.i18n] = el.textContent; });
document.querySelectorAll('[data-i18n-html]').forEach((el) => { english[el.dataset.i18nHtml] = el.innerHTML; });
english['dl.for'] = 'Download for';

function say(key, lang) {
  return (T[lang] && T[lang][key]) || english[key];
}

function setLanguage(lang) {
  if (!T[lang]) lang = 'en';
  document.documentElement.lang = lang;
  document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = say(el.dataset.i18n, lang); });
  document.querySelectorAll('[data-i18n-html]').forEach((el) => { el.innerHTML = say(el.dataset.i18nHtml, lang); });
  document.querySelectorAll('.lang button').forEach((b) => b.classList.toggle('on', b.dataset.lang === lang));
  localStorage.setItem('bilig-lang', lang);
  showHeroDownload(lang);
}

// ---------- Downloads ----------

const PLATFORMS = {
  windows: { name: 'Windows', file: 'Bilig-Windows-Setup.exe' },
  mac: { name: 'Mac', file: 'Bilig-macOS.dmg' },
  linux: { name: 'Linux', file: 'Bilig-Linux-amd64.deb' },
  android: { name: 'Android', file: 'Bilig-Android.apk' },
  ios: { name: 'iPhone', file: null },
};

function detectOs() {
  const ua = navigator.userAgent;
  const platform = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '';
  if (/android/i.test(ua)) return 'android';
  if (/iphone|ipad|ipod/i.test(ua) || (/mac/i.test(platform) && navigator.maxTouchPoints > 1)) return 'ios';
  if (/win/i.test(platform) || /windows/i.test(ua)) return 'windows';
  if (/mac/i.test(platform) || /mac os/i.test(ua)) return 'mac';
  if (/linux|x11/i.test(platform + ua)) return 'linux';
  return null;
}

const os = detectOs();

function showHeroDownload(lang) {
  const button = document.getElementById('hero-download');
  const label = document.getElementById('hero-download-label');
  const icon = document.getElementById('hero-os-icon');
  const p = os && PLATFORMS[os];
  if (!p || !p.file) {
    button.href = '#download';
    label.textContent = say('hero.download', lang);
    icon.innerHTML = '';
    return;
  }
  button.href = LATEST + p.file;
  label.textContent = lang === 'uz' ? `${p.name} uchun yuklab olish` : `${say('dl.for', lang)} ${p.name}`;
  const svg = document.querySelector(`.platform[data-os="${os}"] .p-icon svg`);
  icon.innerHTML = svg ? svg.outerHTML : '';
}

document.querySelectorAll('[data-file]').forEach((a) => { a.href = LATEST + a.dataset.file; });
document.getElementById('all-releases').href = `${REPO}/releases`;
document.getElementById('footer-github').href = REPO;
if (os) {
  const card = document.querySelector(`.platform[data-os="${os}"]`);
  if (card) {
    card.classList.add('mine');
    card.parentElement.prepend(card);
  }
}

// ---------- Language ----------

document.querySelectorAll('.lang button').forEach((b) => b.addEventListener('click', () => setLanguage(b.dataset.lang)));
const saved = localStorage.getItem('bilig-lang');
const browser = (navigator.language || 'en').slice(0, 2).toLowerCase();
setLanguage(saved || (T[browser] ? browser : 'en'));

// ---------- Motion ----------

const nav = document.querySelector('.nav');
addEventListener('scroll', () => nav.classList.toggle('scrolled', scrollY > 8), { passive: true });

const watcher = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (e.isIntersecting) {
      e.target.classList.add('seen');
      watcher.unobserve(e.target);
    }
  }
}, { threshold: 0.12 });
document.querySelectorAll('.steps li, .feature, .card, .wide-shot, .platform, .faq details').forEach((el) => {
  el.classList.add('reveal');
  watcher.observe(el);
});
