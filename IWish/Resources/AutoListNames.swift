import Foundation

/// Культурно-релевантные наборы автогенерируемых названий списков.
/// Не дословный перевод — каждый язык отражает реальные поводы в своей культуре.
enum AutoListNames {

    /// Возвращает массив культурно-релевантных названий для текущего языка юзера.
    /// Fallback на EN если язык не поддержан.
    static func current() -> [String] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let script = Locale.current.language.script?.identifier
        let code: String
        if lang == "zh" && (script == "Hans" || script == nil) {
            code = "zh-Hans"
        } else if lang == "pt" {
            code = "pt-BR"
        } else {
            code = lang
        }
        return byLocale[code] ?? byLocale["en"] ?? []
    }

    /// Per-locale наборы. Не дословный перевод друг друга — каждый локально-релевантный.
    private static let byLocale: [String: [String]] = [
        "ru": ru,
        "en": en,
        "es": es,
        "de": de,
        "fr": fr,
        "it": it,
        "ja": ja,
        "zh-Hans": zhHans,
        "ko": ko,
        "pt-BR": ptBR
    ]

    // MARK: - RU (~150)

    private static let ru: [String] = [
        // Эмоции / мечты
        "Мечты", "Хотелки", "Хотелочки", "Желейка", "Мои находки",
        "Идеи", "Избранное", "Заветное", "Чтобы не забыть", "Просто хочу",
        "Для души", "Коплю на мечту", "Зацепило", "Влюбилась", "Влюбился",
        "Не выходит из головы", "Очень хочется", "Соблазны", "Слабости", "Маленькие радости",
        "Тёплые мысли", "Романтика", "Просто красиво", "По зову сердца", "Просто так",

        // События / праздники
        "День рождения", "Новый год", "На 8 марта", "На 23 февраля", "На 14 февраля",
        "На годовщину", "На свадьбу", "На юбилей", "На выпускной", "На новоселье",
        "На именины", "Тайный Санта", "Новогодние подарки", "Под ёлку", "На корпоратив",
        "Подарки маме", "Подарки папе", "Подарки бабушке", "Подарки дедушке",
        "Подарки сестре", "Подарки брату", "Подарки подруге", "Подарки другу",
        "Подарки коллегам", "Подарки половинке", "Идеи для детей", "Сюрпризы",
        "На Пасху", "На крестины", "На рождение",

        // Категории
        "Книги", "Гаджеты", "Техника", "Одежда", "Обувь",
        "Косметика", "Парфюм", "Украшения", "Аксессуары", "Сумки",
        "Кухня", "Уют дома", "Интерьер", "Спорт", "Здоровье",
        "Хобби", "Творчество", "Игры", "Музыка", "Кино",
        "Сериалы", "Подкасты", "Курсы", "Обучение", "Профессия",
        "Нон-фикшн", "Художка", "Манга", "Комиксы", "Настолки",

        // Путешествия
        "Путешествия", "Куда поехать", "Города мечты", "Страны", "Маршруты",
        "Отпуск", "Выходные", "Походы", "Кемпинг", "Море",
        "Горы", "Северное сияние", "Япония", "Бали", "Европа",
        "Грузия", "Турция", "Тёплые края", "Зимний отпуск", "Лето",

        // Работа / дом
        "Для работы", "Для учёбы", "Для дома", "Для квартиры", "На дачу",
        "В машину", "В офис", "Ремонт", "Переезд", "Сад и огород",
        "На балкон", "В ванную", "На кухню", "В спальню", "В гостиную",
        "Рабочее место", "Уход за собой", "Бьюти-маст", "ЗОЖ", "Биохакинг",

        // Игривое
        "Глупые мечты", "Импульсивные покупки", "Когда-нибудь", "Лень-список", "По настроению",
        "Список баловства", "Понравилось", "Глаз положил", "Карманный список", "Зацепило сердце",
        "Маленький список", "Просто список", "Вишлист", "Хотелочки-хотелки", "Список желаний",
        "Список жизни", "Bucket list", "Список целей", "Через год", "Через 5 лет",
        "Большая мечта", "Маленькая мечта", "Реалистично", "Мечта-мечта",

        // Сезонное
        "Весна", "Лето", "Осень", "Зима", "Чёрная пятница",
        "Сезон распродаж", "Не забыть", "Подарок себе", "Награда себе", "С зарплаты",
        "С премии", "Накопления", "Маленькие радости", "Раз в год", "Летний лук",

        // Дети
        "Для малыша", "Для малышки", "В детскую", "Первый день рождения", "В школу",
        "Игрушки", "Развивашки", "Детские книги", "Детский спорт", "Семейный отпуск",

        // Стиль
        "Эстетика", "Минимализм", "Уютное", "Винтаж", "Хюгге",
        "Скандинавский стиль", "Лофт", "Бохо", "Pinterest", "Капсульный гардероб",

        // Прочее
        "Попробовать", "Любопытно", "Эксперимент", "Новый опыт", "Хочу научиться",
        "Прокачать себя", "Саморазвитие", "Мотивация", "На полях", "Случайные хотелки"
    ]

    // MARK: - EN (~150)

    private static let en: [String] = [
        // Emotions / dreams
        "Wishlist", "My wishlist", "My finds", "Dream list", "Bucket list",
        "Just want it", "Maybe one day", "Saving for", "Caught my eye", "Obsessed",
        "Cannot stop thinking", "Heart wants", "Soft spot", "Tempting", "Little joys",
        "For the soul", "Romance corner", "Just because", "Inner voice", "My weakness",

        // Holidays
        "Christmas", "Christmas list", "For under the tree", "Holiday season", "Secret Santa",
        "Office Secret Santa", "Birthday", "Birthday ideas", "My birthday", "Anniversary",
        "Wedding", "Wedding registry", "Engagement", "Bridal shower", "Baby shower",
        "Valentine\u{2019}s Day", "Mother\u{2019}s Day", "Father\u{2019}s Day", "Graduation", "Housewarming",
        "Easter basket", "Thanksgiving", "Hanukkah", "Halloween", "New Year",
        "Galentine\u{2019}s", "Promotion gift", "Retirement gift",

        // Gifts
        "Gifts for mom", "Gifts for dad", "Gifts for grandma", "Gifts for grandpa",
        "Gifts for partner", "Gifts for boyfriend", "Gifts for girlfriend", "Gifts for husband", "Gifts for wife",
        "Gifts for sister", "Gifts for brother", "Gifts for friends", "Gifts for best friend",
        "Gifts for kids", "Gifts for teacher", "Gifts for coworkers", "Gifts for the host",

        // Categories
        "Books", "Books to read", "Gadgets", "Tech", "Clothes",
        "Shoes", "Sneakers", "Beauty", "Skincare", "Makeup",
        "Fragrance", "Jewelry", "Accessories", "Bags", "Watches",
        "Sunglasses", "Activewear", "Loungewear", "Workwear",

        // Home
        "For home", "Apartment", "First apartment", "New home", "Renovation",
        "Kitchen", "Bedroom", "Bathroom", "Living room", "Office",
        "Workspace", "Desk setup", "Backyard", "Patio", "Plants",

        // Travel
        "Travel", "Bucket list trips", "Japan trip", "Europe", "Italy",
        "Paris", "London", "New York", "Beach getaway", "Road trip",
        "Camping", "Hiking gear", "Ski trip", "Honeymoon", "Cruise",
        "Weekend getaway", "Backpacking", "Vacation mode",

        // Seasons / sales
        "Black Friday", "Cyber Monday", "Prime Day", "Boxing Day", "Spring refresh",
        "Summer must-haves", "Fall favorites", "Winter cozy", "Back to school",

        // Hobbies
        "Hobbies", "Games", "Board games", "Video games", "Music gear",
        "Vinyl", "Coffee gear", "Tea things", "Camera gear", "Art supplies",
        "Craft supplies", "Baking", "Fitness", "Yoga", "Running",

        // Self-care / playful
        "Self-care", "Treat myself", "Payday treats", "Splurge", "Just looking",
        "Aesthetic", "Cozy vibes", "Minimal", "Pinterest board", "Vibes",
        "Eventually", "One day", "When I save up", "Dreaming", "Window shopping",

        // Kids / family
        "For baby", "Nursery", "Kids\u{2019} room", "Toys", "Educational toys",
        "Kids\u{2019} books", "Family time", "Family trip", "Pet stuff"
    ]

    // MARK: - ES (~120)

    private static let es: [String] = [
        // Emociones
        "Mis deseos", "Lista de deseos", "Mis caprichos", "Antojos", "Cosas que quiero",
        "Para soñar", "Para algún día", "Me encanta", "No puedo parar de pensarlo", "Mis favoritos",
        "Para el alma", "Pequeñas alegrías", "Ahorrando para", "Tentaciones",

        // Fiestas España / LatAm
        "Navidad", "Para Navidad", "Reyes Magos", "Carta a los Reyes", "Año Nuevo",
        "Nochebuena", "Nochevieja", "Día de la Madre", "Día del Padre", "Día de San Valentín",
        "Aniversario", "Boda", "Lista de boda", "Cumpleaños", "Mi cumpleaños",
        "Quinceañera", "Bautizo", "Comunión", "Pascua", "Semana Santa",
        "Día de los Muertos", "Día del Niño", "Amigo Invisible", "Día de Acción de Gracias",

        // Regalos
        "Regalos para mamá", "Regalos para papá", "Regalos para la abuela", "Regalos para el abuelo",
        "Regalos para mi pareja", "Regalos para mi novio", "Regalos para mi novia",
        "Regalos para mi hermana", "Regalos para mi hermano", "Regalos para amigos",
        "Regalos para los niños", "Regalos para el profe", "Regalos para compañeros",

        // Categorías
        "Libros", "Tecnología", "Gadgets", "Ropa", "Zapatos",
        "Belleza", "Maquillaje", "Perfumes", "Joyería", "Accesorios",
        "Bolsos", "Relojes", "Gafas de sol",

        // Casa
        "Para casa", "Mi primer piso", "Mudanza", "Cocina", "Salón",
        "Dormitorio", "Baño", "Terraza", "Balcón", "Jardín",
        "Reforma", "Oficina en casa", "Plantas",

        // Viajes
        "Viajes", "Viaje soñado", "Europa", "Japón", "México",
        "Argentina", "Colombia", "Madrid", "Barcelona", "París",
        "Playa", "Montaña", "Camino de Santiago", "Escapada de fin de semana", "Luna de miel",

        // Sales / temporadas
        "Black Friday", "Buen Fin", "Cyber Monday", "Rebajas", "Rebajas de enero",
        "Rebajas de verano", "Vuelta al cole",

        // Hobbies
        "Aficiones", "Videojuegos", "Juegos de mesa", "Música", "Cine",
        "Series", "Manualidades", "Fotografía", "Cocina", "Deporte",
        "Yoga", "Running", "Gimnasio",

        // Self-care
        "Cuidado personal", "Capricho", "Para mimarme", "Día de spa", "Bienestar",

        // Niños
        "Para el bebé", "Habitación del bebé", "Juguetes", "Cosas del cole", "Cuentos infantiles"
    ]

    // MARK: - DE (~120)

    private static let de: [String] = [
        // Emotionen
        "Wunschliste", "Meine Wünsche", "Meine Funde", "Lieblingssachen", "Träume",
        "Eines Tages", "Verliebt", "Will ich haben", "Spare ich drauf", "Kleine Freuden",
        "Aus dem Bauch heraus", "Verlockungen", "Geht mir nicht aus dem Kopf",

        // Feste
        "Weihnachten", "Weihnachtsgeschenke", "Unterm Tannenbaum", "Heiligabend", "Silvester",
        "Neujahr", "Geburtstag", "Mein Geburtstag", "Geburtstagsideen", "Hochzeit",
        "Hochzeitsliste", "Verlobung", "Hochzeitstag", "Jubiläum", "Taufe",
        "Konfirmation", "Kommunion", "Einschulung", "Schulanfang", "Abitur",
        "Muttertag", "Vatertag", "Valentinstag", "Ostern", "Nikolaus",
        "Wichteln", "Schrottwichteln", "Adventskalender",

        // Geschenke
        "Geschenke für Mama", "Geschenke für Papa", "Geschenke für Oma", "Geschenke für Opa",
        "Geschenke für meinen Partner", "Geschenke für meinen Freund", "Geschenke für meine Freundin",
        "Geschenke für die Schwester", "Geschenke für den Bruder", "Geschenke für Freunde",
        "Geschenke für die Kinder", "Geschenke für Kollegen", "Geschenke für die Lehrerin",

        // Kategorien
        "Bücher", "Technik", "Gadgets", "Kleidung", "Schuhe",
        "Sneaker", "Kosmetik", "Parfum", "Schmuck", "Accessoires",
        "Taschen", "Uhren", "Sonnenbrillen",

        // Zuhause
        "Für zu Hause", "Erste Wohnung", "Umzug", "Küche", "Wohnzimmer",
        "Schlafzimmer", "Badezimmer", "Balkon", "Garten", "Schreibtisch",
        "Homeoffice", "Renovierung", "Einrichtung",

        // Reisen
        "Reisen", "Traumreise", "Skiurlaub", "Berge", "Strandurlaub",
        "Städtetrip", "Wochenendtrip", "Italien", "Spanien", "Frankreich",
        "Japan", "USA", "Mallorca", "Camping", "Roadtrip",
        "Wanderurlaub", "Flitterwochen",

        // Sales
        "Black Friday", "Cyber Monday", "Winterschlussverkauf", "Sommerschlussverkauf",

        // Hobbys
        "Hobbys", "Brettspiele", "Videospiele", "Musik", "Kamera",
        "Kaffee", "Backen", "Sport", "Fitness", "Yoga", "Laufen",

        // Self-care
        "Mir selbst etwas gönnen", "Wellness", "Verwöhntag", "Ich-Zeit",

        // Kinder
        "Fürs Baby", "Kinderzimmer", "Spielzeug", "Lernspielzeug", "Kinderbücher",
        "Schulsachen"
    ]

    // MARK: - FR (~120)

    private static let fr: [String] = [
        // Émotions
        "Ma wishlist", "Mes envies", "Mes coups de cœur", "Mes trouvailles", "Liste de souhaits",
        "Mes rêves", "Un jour peut-être", "Pour le plaisir", "J\u{2019}adore", "Pour plus tard",
        "J\u{2019}économise pour", "Tentations", "Petits plaisirs", "Pour l\u{2019}âme",

        // Fêtes
        "Noël", "Cadeaux de Noël", "Sous le sapin", "Réveillon", "Nouvel An",
        "Jour de l\u{2019}An", "Saint-Valentin", "Anniversaire", "Mon anniversaire", "Fête des Mères",
        "Fête des Pères", "Fête des Grands-Mères", "Mariage", "Liste de mariage", "PACS",
        "Anniversaire de mariage", "Baptême", "Communion", "Pâques", "Épiphanie",
        "Chandeleur", "Fête de la Musique", "Père Noël secret", "Galette des Rois",

        // Cadeaux
        "Cadeaux pour maman", "Cadeaux pour papa", "Cadeaux pour mamie", "Cadeaux pour papi",
        "Cadeaux pour mon copain", "Cadeaux pour ma copine", "Cadeaux pour mon conjoint",
        "Cadeaux pour ma sœur", "Cadeaux pour mon frère", "Cadeaux pour amis",
        "Cadeaux pour les enfants", "Cadeaux pour collègues", "Cadeaux d\u{2019}hôte",

        // Catégories
        "Livres", "Tech", "Gadgets", "Vêtements", "Chaussures",
        "Beauté", "Maquillage", "Parfums", "Bijoux", "Accessoires",
        "Sacs", "Montres", "Lunettes",

        // Maison
        "Pour la maison", "Premier appart", "Déménagement", "Cuisine", "Salon",
        "Chambre", "Salle de bain", "Balcon", "Jardin", "Bureau",
        "Télétravail", "Rénovation", "Déco",

        // Voyages
        "Voyages", "Voyage de rêve", "Week-end", "Escapade", "Japon",
        "Italie", "Espagne", "Portugal", "Provence", "Côte d\u{2019}Azur",
        "Paris", "New York", "Bali", "Road trip", "Camping",
        "Ski", "Plage", "Lune de miel",

        // Soldes
        "Black Friday", "Soldes", "Soldes d\u{2019}été", "Soldes d\u{2019}hiver", "French Days",

        // Hobbies
        "Loisirs", "Jeux", "Jeux de société", "Jeux vidéo", "Musique",
        "Cinéma", "Photo", "Cuisine", "Pâtisserie", "Sport",
        "Yoga", "Course à pied",

        // Self-care
        "Me faire plaisir", "Petit luxe", "Spa", "Bien-être",

        // Enfants
        "Pour bébé", "Chambre de bébé", "Jouets", "Livres pour enfants", "Rentrée des classes"
    ]

    // MARK: - IT (~120)

    private static let it: [String] = [
        // Emozioni
        "Lista dei desideri", "I miei desideri", "I miei tesori", "Le mie scoperte", "Sogni",
        "Un giorno", "Voglio averlo", "Sto risparmiando", "Tentazioni", "Piccole gioie",
        "Per l\u{2019}anima", "Mi ha conquistato", "Non riesco a smettere di pensarci",

        // Feste
        "Natale", "Regali di Natale", "Sotto l\u{2019}albero", "Vigilia di Natale", "Capodanno",
        "Befana", "Epifania", "San Valentino", "Compleanno", "Il mio compleanno",
        "Festa della Mamma", "Festa del Papà", "Festa della Donna", "Festa dei Nonni",
        "Anniversario", "Matrimonio", "Lista nozze", "Battesimo", "Cresima",
        "Comunione", "Laurea", "Pasqua", "Ferragosto", "Halloween",

        // Regali
        "Regali per la mamma", "Regali per il papà", "Regali per la nonna", "Regali per il nonno",
        "Regali per il fidanzato", "Regali per la fidanzata", "Regali per il partner",
        "Regali per mia sorella", "Regali per mio fratello", "Regali per amici",
        "Regali per i bambini", "Regali per i colleghi", "Regali per la maestra",

        // Categorie
        "Libri", "Tecnologia", "Gadget", "Vestiti", "Scarpe",
        "Sneakers", "Bellezza", "Trucchi", "Profumi", "Gioielli",
        "Accessori", "Borse", "Orologi", "Occhiali da sole",

        // Casa
        "Per casa", "Prima casa", "Trasloco", "Cucina", "Salotto",
        "Camera da letto", "Bagno", "Balcone", "Giardino", "Scrivania",
        "Smart working", "Ristrutturazione", "Arredamento",

        // Viaggi
        "Viaggi", "Viaggio dei sogni", "Weekend", "Mare", "Montagna",
        "Settimana bianca", "Roma", "Milano", "Firenze", "Venezia",
        "Sicilia", "Sardegna", "Giappone", "Spagna", "Portogallo",
        "New York", "Crociera", "Luna di miele",

        // Saldi
        "Black Friday", "Saldi", "Saldi estivi", "Saldi invernali", "Cyber Monday",

        // Hobby
        "Hobby", "Giochi da tavolo", "Videogiochi", "Musica", "Cinema",
        "Fotografia", "Cucina", "Sport", "Palestra", "Yoga",
        "Corsa", "Bici",

        // Cura di sé
        "Per coccolarmi", "Coccola", "Spa", "Benessere",

        // Bambini
        "Per il bebè", "Cameretta", "Giocattoli", "Libri per bambini", "Ritorno a scuola"
    ]

    // MARK: - JA (~100)

    private static let ja: [String] = [
        // 気持ち
        "ほしいものリスト", "ウィッシュリスト", "夢リスト", "お気に入り", "気になるもの",
        "いつか欲しい", "ずっと欲しかった", "貯金中", "心が動いた", "ご褒美リスト",

        // イベント
        "誕生日", "私の誕生日", "クリスマス", "クリスマスプレゼント", "お正月",
        "バレンタインデー", "ホワイトデー", "母の日", "父の日", "敬老の日",
        "こどもの日", "ひな祭り", "節分", "七夕", "お盆",
        "結婚記念日", "結婚式", "婚約", "成人式", "卒業祝い",
        "入学祝い", "出産祝い", "内祝い", "引っ越し祝い", "新築祝い",

        // 贈り物
        "ママへのプレゼント", "パパへのプレゼント", "祖母へのプレゼント", "祖父へのプレゼント",
        "彼へのプレゼント", "彼女へのプレゼント", "夫へのプレゼント", "妻へのプレゼント",
        "姉妹へのプレゼント", "兄弟へのプレゼント", "友達へのプレゼント",
        "子供へのプレゼント", "同僚へのプレゼント", "先生へのプレゼント",

        // カテゴリー
        "本", "ガジェット", "家電", "ファッション", "靴",
        "スニーカー", "コスメ", "スキンケア", "香水", "アクセサリー",
        "ジュエリー", "バッグ", "時計", "サングラス",

        // 家
        "おうち時間", "新生活", "引っ越し", "キッチン", "リビング",
        "寝室", "バスルーム", "ベランダ", "書斎", "デスク周り",
        "在宅ワーク", "インテリア",

        // 旅行
        "旅行", "夢の旅", "京都", "東京", "大阪",
        "沖縄", "北海道", "ハワイ", "韓国", "台湾",
        "ヨーロッパ", "週末旅行", "温泉旅行", "新婚旅行",

        // セール
        "ボーナス", "セール", "楽天セール", "Amazonセール", "ブラックフライデー",

        // 趣味
        "趣味", "ゲーム", "アニメ", "漫画", "音楽",
        "映画", "カメラ", "コーヒー", "お茶", "料理",
        "お菓子作り", "ヨガ", "ランニング",

        // 自分へのご褒美
        "自分へのご褒美", "ちょっと贅沢", "癒し", "おうちカフェ",

        // 子供
        "ベビー用品", "子供部屋", "おもちゃ", "知育玩具", "絵本",
        "入園準備", "入学準備"
    ]

    // MARK: - ZH-Hans (~100)

    private static let zhHans: [String] = [
        // 心情
        "心愿单", "我的心愿", "我的发现", "梦想清单", "种草清单",
        "想要的", "总有一天", "存钱中", "心动了", "舍不得",
        "犒劳自己", "小确幸",

        // 节日
        "春节", "新年", "元旦", "春节礼物", "压岁钱",
        "元宵节", "情人节", "七夕", "妇女节", "母亲节",
        "父亲节", "儿童节", "教师节", "端午节", "中秋节",
        "国庆", "重阳节", "圣诞节", "圣诞礼物", "万圣节",
        "感恩节", "复活节",

        // 礼物
        "给妈妈的礼物", "给爸爸的礼物", "给奶奶的礼物", "给爷爷的礼物",
        "给男朋友的礼物", "给女朋友的礼物", "给老公的礼物", "给老婆的礼物",
        "给姐姐的礼物", "给哥哥的礼物", "给弟弟的礼物", "给妹妹的礼物",
        "给朋友的礼物", "给闺蜜的礼物", "给同事的礼物", "给老师的礼物",
        "给孩子的礼物", "生日礼物", "我的生日",

        // 类别
        "数码", "电子产品", "服装", "鞋子", "运动鞋",
        "美妆", "护肤", "彩妆", "香水", "首饰",
        "配饰", "包包", "手表", "墨镜",

        // 家
        "家居", "新家", "搬家", "厨房", "客厅",
        "卧室", "浴室", "阳台", "书房", "桌面",
        "居家办公", "装修",

        // 旅行
        "旅行", "梦想之旅", "国内游", "出国游", "日本",
        "韩国", "泰国", "新加坡", "欧洲", "美国",
        "北京", "上海", "成都", "三亚", "周末游",
        "蜜月旅行",

        // 购物节
        "双十一", "双12", "618", "黑五", "年货节",
        "春季新品", "夏日好物",

        // 兴趣
        "兴趣爱好", "游戏", "桌游", "音乐", "电影",
        "摄影", "咖啡", "茶", "烘焙", "健身",
        "瑜伽", "跑步",

        // 自我
        "犒赏自己", "小奢侈", "SPA", "保养",

        // 孩子
        "宝宝用品", "儿童房", "玩具", "益智玩具", "绘本",
        "开学季"
    ]

    // MARK: - KO (~100)

    private static let ko: [String] = [
        // 감정
        "위시리스트", "내 위시리스트", "찜한 것", "갖고 싶은 것", "꿈의 목록",
        "언젠가는", "사고 싶다", "모으는 중", "마음에 들어", "나를 위한 선물",
        "소소한 행복",

        // 명절 / 기념일
        "설날", "추석", "크리스마스", "크리스마스 선물", "새해",
        "발렌타인데이", "화이트데이", "빼빼로데이", "어버이날", "어머니날",
        "아버지날", "스승의 날", "어린이날", "생일", "내 생일",
        "결혼기념일", "결혼식", "약혼", "돌잔치", "백일",
        "입학 선물", "졸업 선물", "취업 선물", "집들이",

        // 선물
        "엄마 선물", "아빠 선물", "할머니 선물", "할아버지 선물",
        "남자친구 선물", "여자친구 선물", "남편 선물", "아내 선물",
        "언니 선물", "오빠 선물", "동생 선물",
        "친구 선물", "베프 선물", "직장 동료 선물", "선생님 선물",
        "아이 선물",

        // 카테고리
        "책", "전자기기", "가전", "패션", "옷",
        "신발", "스니커즈", "화장품", "스킨케어", "메이크업",
        "향수", "주얼리", "악세사리", "가방", "시계",
        "선글라스",

        // 집
        "홈인테리어", "자취", "이사", "주방", "거실",
        "침실", "화장실", "베란다", "서재", "책상",
        "재택근무", "인테리어",

        // 여행
        "여행", "꿈의 여행", "제주도", "부산", "서울",
        "강릉", "일본", "오사카", "도쿄", "유럽",
        "미국", "동남아", "태국", "베트남", "주말 여행",
        "신혼여행",

        // 쇼핑
        "블랙프라이데이", "광군제", "코리아세일페스타", "연말 세일",

        // 취미
        "취미", "게임", "보드게임", "음악", "영화",
        "사진", "카메라", "커피", "베이킹", "운동",
        "요가", "러닝", "헬스",

        // 자기관리
        "나를 위한 선물", "셀프 선물", "스파", "휴식",

        // 아이
        "아기용품", "아이방", "장난감", "교구", "동화책"
    ]

    // MARK: - PT-BR (~120)

    private static let ptBR: [String] = [
        // Emoções
        "Lista de desejos", "Meus desejos", "Minha wishlist", "Meus achados", "Sonhos",
        "Um dia", "Quero muito", "Juntando dinheiro", "Apaixonei", "Não saiu da cabeça",
        "Pequenas alegrias", "Para a alma", "Tentações",

        // Festas brasileiras
        "Natal", "Presentes de Natal", "Amigo Secreto", "Amigo Oculto", "Ano Novo",
        "Réveillon", "Páscoa", "Carnaval", "Festa Junina", "São João",
        "Dia das Mães", "Dia dos Pais", "Dia dos Namorados", "Dia das Crianças", "Dia dos Avós",
        "Aniversário", "Meu aniversário", "Bodas", "Casamento", "Chá de panela",
        "Chá de bebê", "Chá revelação", "Batizado", "Formatura", "Festa de 15 anos",
        "Dia do Professor", "Halloween", "Black November",

        // Presentes
        "Presentes para mamãe", "Presentes para papai", "Presentes para vovó", "Presentes para vovô",
        "Presentes para namorado", "Presentes para namorada", "Presentes para marido", "Presentes para esposa",
        "Presentes para irmã", "Presentes para irmão", "Presentes para amigos", "Presentes para melhor amiga",
        "Presentes para filhos", "Presentes para colegas", "Presentes para professora",

        // Categorias
        "Livros", "Tecnologia", "Eletrônicos", "Roupas", "Sapatos",
        "Tênis", "Beleza", "Maquiagem", "Skincare", "Perfumes",
        "Joias", "Bijuterias", "Acessórios", "Bolsas", "Relógios",
        "Óculos de sol",

        // Casa
        "Para casa", "Primeira casa", "Mudança", "Cozinha", "Sala",
        "Quarto", "Banheiro", "Varanda", "Jardim", "Home office",
        "Escritório", "Reforma", "Decoração",

        // Viagens
        "Viagem", "Viagem dos sonhos", "Praia", "Praia do Norte", "Nordeste",
        "Rio de Janeiro", "São Paulo", "Florianópolis", "Bahia", "Fernando de Noronha",
        "Europa", "Estados Unidos", "Disney", "Argentina", "Chile",
        "Portugal", "Japão", "Lua de mel", "Mochilão", "Final de semana",

        // Sales
        "Black Friday", "Black November", "Cyber Monday", "Liquidação", "Liquida BR",

        // Hobbies
        "Hobbies", "Jogos", "Videogame", "Jogos de tabuleiro", "Música",
        "Cinema", "Séries", "Fotografia", "Café", "Confeitaria",
        "Academia", "Yoga", "Corrida",

        // Self-care
        "Me presentear", "Pequeno luxo", "Spa", "Bem-estar", "Dia da beleza",

        // Crianças
        "Para o bebê", "Quarto do bebê", "Brinquedos", "Brinquedos educativos", "Livros infantis",
        "Volta às aulas"
    ]
}
