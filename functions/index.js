// IWish Cloud Functions — entry point.
//
// 1. onSharedItemWritten — Firestore trigger на shared_wishlists/{wid}/items/{iid}.
//    Шлёт FCM push участникам (кроме автора) с базовой инфой:
//    title="I Wish", body="<userName> {action} желание".
//    Wishlist name и item name НЕ включаются в body — E2E шифрование, CF не знает их.
//    Имя желания показывает NotificationServiceExtension на устройстве: CF пробрасывает
//    короткое зашифрованное имя (data.encryptedName), NSE расшифровывает локально ключом
//    из shared Keychain. Сам сервер расшифровать не может.
//    Также: per-user unread badge, фильтр по notification preferences, тихий reorder.
//
// 2. onSharedWishlistWritten — то же для самого wishlist'а (название/обложка изменены).
//    Реализуется при необходимости.

const admin = require('firebase-admin');
admin.initializeApp();

const { onSharedItemWritten } = require('./src/pushSharedItemWritten');

exports.onSharedItemWritten = onSharedItemWritten;
