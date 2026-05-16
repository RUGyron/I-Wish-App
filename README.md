<div align="center">

# IWish ✨

**Списки желаний, которые видишь только ты и те, кому ты разрешила.**

[Скачать в App Store](https://apps.apple.com/app/id6762267281?ct=github-readme&mt=8) · [Веб-сайт](https://rugyron.github.io/I-Wish-App/promo) · [Документация для разработчиков](#документация-для-разработчиков)

![License](https://img.shields.io/github/license/RUGyron/I-Wish-App?style=flat-square)
![iOS](https://img.shields.io/badge/iOS-26%2B-blue?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat-square)
![Free Forever](https://img.shields.io/badge/free-forever-brightgreen?style=flat-square)
![No Ads](https://img.shields.io/badge/no-ads-blueviolet?style=flat-square)
[![App Store](https://img.shields.io/badge/App_Store-Download-000?style=flat-square&logo=apple)](https://apps.apple.com/app/id6762267281?ct=github-readme-badge&mt=8)

<img src="docs/assets/hero.png" alt="IWish — приватные списки желаний" width="800"/>

</div>

---

## Что это

IWish — это приложение для iPhone, в котором ты ведёшь свои списки желаний и делишься ими с близкими.

Главная фишка — **ничего не утекает наружу**. Ни сервер, ни разработчик, ни Firebase, на котором работает приложение, не видят содержимое твоих вишлистов. Их видят только те, кому ты сама дала ссылку.

Сделано как pet-проект одним человеком. Без подписок, без рекламы, без премиум-функций «купи чтобы открылось». Всё бесплатно, навсегда. Исходный код открыт — каждый может убедиться, что приложение действительно делает то, что обещает.

## Почему IWish

- 🔒 **Приватно по умолчанию.** Содержимое списков шифруется прямо на твоём iPhone. Никто кроме тебя и приглашённых не сможет это прочитать — даже если сервер взломают.
- 🎁 **Бесплатно навсегда.** Никаких подписок, никакой рекламы, никаких «Pro»-уровней. Это не бизнес, это проект для людей.
- 🪶 **Без аккаунтов и паролей.** Вход через Apple ID одним тапом. Никаких email-рассылок, никаких «придумайте пароль».
- 🤝 **Совместное редактирование.** Кидаешь близкому QR-код или ссылку — он открывает твой список и может добавлять пункты. Удобно для дней рождения и совместных покупок.
- 🍎 **Нативный iOS 26.** Сделано в новом дизайне Liquid Glass. Работает плавно, выглядит как часть системы.
- 🌍 **Open Source.** MIT-лицензия. Код можно посмотреть, форкнуть, собрать самому.

## Скриншоты

> *Placeholder — Влад, сюда нужно положить 4–6 скринов в `docs/assets/`. Названия: `screen-1.png` … `screen-6.png`. Размер ~1290×2796 (iPhone 16 Pro Max) или экспорт из ASC. Рекомендую: 1) главный экран со списками, 2) экран wishlist с желаниями, 3) добавление желания, 4) шаринг (QR), 5) тёмная и светлая темы рядом, 6) настройки/иконки.*

<p align="center">
  <img src="docs/assets/screen-1.png" width="200" alt="Главный экран"/>
  <img src="docs/assets/screen-2.png" width="200" alt="Wishlist"/>
  <img src="docs/assets/screen-3.png" width="200" alt="Добавление желания"/>
  <img src="docs/assets/screen-4.png" width="200" alt="Шаринг через QR"/>
</p>
<p align="center">
  <img src="docs/assets/screen-5.png" width="200" alt="Темы"/>
  <img src="docs/assets/screen-6.png" width="200" alt="Настройки"/>
</p>

## Как пользоваться

1. **Скачай** [в App Store](https://apps.apple.com/app/id6762267281?ct=github-readme-howto&mt=8).
2. **Войди через Apple** — один тап, без паролей.
3. **Создай wishlist** — назови его («ДР 2026», «Хочу когда-нибудь», «Подарки маме»).
4. **Добавляй желания** — название, фото, цена, ссылка, важность (must / maybe / idea).
5. **Поделись** — нажми «Поделиться», получи QR-код или ссылку, кинь близкому в iMessage / Telegram / любым другим способом.

Готово. Тот, кто открыл ссылку, видит твой список и может добавлять туда свои предложения.

---

## Документация для разработчиков

### Технологический стек

- **Платформа:** iOS 26+
- **Язык:** Swift 6, SwiftUI
- **Локальное хранилище:** SwiftData
- **Облако:** Firebase Firestore (Spark plan)
- **Авторизация:** Firebase Auth + Sign in with Apple
- **Криптография:** Apple CryptoKit (AES-GCM-256)
- **Хранение ключей:** iCloud Keychain (с синхронизацией между устройствами одного Apple ID)
- **Push:** Firebase Cloud Messaging (в разработке, v1.2.0)

### Архитектура шифрования

Каждый wishlist имеет свой симметричный ключ AES-GCM-256, сгенерированный на устройстве при создании. Контент (название списка, желания, фото, цены, ссылки, описания) шифруется этим ключом локально и только потом улетает в Firestore. В базе лежат **зашифрованные блобы** + метаданные (id, owner uid, timestamps).

Ключ хранится в **iCloud Keychain** — между устройствами одного Apple ID он синхронизируется автоматически Apple-инфраструктурой (E2E, Apple сам не имеет к ключу доступа).

При шаринге wishlist'а ключ передаётся **в URL fragment** (`https://rugyron.github.io/I-Wish-App/wishlist/<id>#k=<base64-key>`). Fragment по стандарту HTTP **не уходит на сервер** — браузер/iOS обрабатывают его на клиенте, deep-link handler ловит и передаёт в приложение. Сервер видит только id wishlist'а в path, без ключа.

### Лимиты (Spark plan)

- 30 wishlist'ов на пользователя
- 50 желаний в одном wishlist'е

При росте аудитории лимиты пересмотрим, но политика «бесплатно навсегда» — фиксированная.

### Сборка локально

**Требования:**
- macOS 15+ (Sequoia или новее)
- Xcode 26+
- iOS 26 SDK
- Apple Developer account (бесплатный тоже подойдёт для запуска на своём устройстве)

**Шаги:**

```bash
git clone https://github.com/RUGyron/I-Wish-App.git
cd I-Wish-App
open IWish.xcodeproj
```

В Xcode:
1. Подставь свой `GoogleService-Info.plist` от своего Firebase-проекта в `IWish/`.
2. Поменяй Bundle Identifier на свой (или оставь и собирай только локально без публикации).
3. В Signing & Capabilities выбери свою команду.
4. Cmd+R.

**Известный quirk:** на macOS Sequoia при codesign может вылетать ошибка про `com.apple.provenance` xattr. Решение — добавить в Build Settings:
```
OTHER_CODE_SIGN_FLAGS = --strip-disallowed-xattrs
```

### Безопасность — что мы можем и чего не можем

**Что зашифровано E2E (даже разработчик и Firebase не видят):**
- Названия wishlist'ов
- Все поля желаний (название, фото, цена, ссылка, описание, важность)

**Что НЕ зашифровано (хранится в открытом виде):**
- Firebase Auth user record — email (если ты дал реальный, а не приватный Apple Relay), Apple user identifier. Это нужно чтобы вообще логиниться.
- Метаданные wishlist'а — id, owner uid, кто соавтор, timestamps.
- Push-токены устройств (когда заведём пуши).

**Threat model:**
- ✅ Защищены от: утечки базы Firestore, компрометации serverside, любопытного админа (меня).
- ⚠️ Не защищены от: компрометации твоего устройства, компрометации Apple ID (потому что ключ синхронизируется через iCloud Keychain — тот, кто получит доступ к твоему iCloud, получит и доступ к ключам).
- ⚠️ Если ты делишься ссылкой через мессенджер — безопасность ссылки = безопасность мессенджера. Не публикуй share-ссылки на wishlist в открытых местах.

Релевантный код:
- Шифрование: `IWish/Services/Crypto/` (CryptoKit-обёртки)
- Хранение ключей: `IWish/Services/KeychainStore.swift`
- Парсинг share-link с fragment'ом: `IWish/Services/DeepLink/`

> Если найдёшь уязвимость — напиши на `pivosh098@gmail.com` до публикации. Спасибо.

### Contributing

PR welcome. Если хочешь крупную фичу — сначала открой issue, обсудим. Маленькие фиксы можно сразу PR.

**Code style:** стандартный SwiftFormat / стиль такой же как в репе. Никаких force unwrap без причины, никаких принтов в release, локализация — через String catalog.

**Что бы пригодилось:**
- Локализации (сейчас RU + EN)
- iPad-адаптация (приложение работает, но не оптимизирована вёрстка)
- Парсинг новых маркетплейсов в auto-fill ссылок

### Дорожная карта (v1.2.0, в TestFlight)

- 🔄 Парсинг ссылок с маркетплейсов (Wildberries, Ozon, Amazon → автозаполнение названия, фото, цены)
- 🔔 Push-уведомления о добавлении желаний в общий wishlist
- 🇬🇧 Доработка английской локализации

---

## License

MIT © [Vladislav Pivosh (RUGyron)](https://github.com/RUGyron)

См. [LICENSE](./LICENSE).

## Связаться

- 📧 Email: [pivosh098@gmail.com](mailto:pivosh098@gmail.com)
- ⭐ [Оставить отзыв в App Store](https://apps.apple.com/app/id6762267281?ct=github-readme-contact&mt=8)
- 🐛 [Открыть issue](https://github.com/RUGyron/I-Wish-App/issues/new)

---

<div align="center">

Сделано с любовью одним человеком. Без бизнес-плана, без раундов, без рекламы.

[Скачать в App Store →](https://apps.apple.com/app/id6762267281?ct=github-readme-footer&mt=8)

</div>
