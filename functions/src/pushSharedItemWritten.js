// Firestore trigger: shared_wishlists/{wishlistID}/items/{itemID} → push участникам.
//
// E2E constraint: контент item зашифрован (encryptedPayload). На сервере мы НЕ знаем
// имя желания и имя списка. Поэтому push title="I Wish", body содержит только plaintext
// metadata: userName автора + действие (added / updated / deleted).
//
// v1.2.1 изменения:
//  - SKIP push если encryptedPayload не изменился (reorder / archive-toggle / lastModifiedByUID-
//    only). Реордер списка больше не шлёт пуши вообще (Влад: "о порядке уведомлять не нужно").
//  - Per-user unread counter (users/{uid}.unreadCount, atomic transaction) → реальный badge
//    на иконке, а не захардкоженная 1. Клиент обнуляет при заходе в приложение.
//  - Notification preferences: пропускаем получателя если users/{uid}.pushEnabled == false
//    (глобальный тоггл) ИЛИ memberships/{uid}_{wid}.notificationsEnabled == false (per-list).
//    Отсутствие поля = true (старые данные продолжают получать пуши, без регресса).
//  - encryptedName: если у item-документа есть отдельное короткое зашифрованное имя, пробрасываем
//    его в data payload (base64) — NotificationServiceExtension расшифрует на устройстве и покажет
//    название желания фиксированной длины. Сам сервер расшифровать не может (E2E).
//
// Имя автора достаём из памяти membership-документа (`memberships/{uid}_{wid}.userName` plaintext).
// Локаль получателя из users/{uid}.userLocale — выбираем язык body соответственно.

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const { VertexAI } = require('@google-cloud/vertexai');

const REGION = 'us-central1';
const PROJECT_ID = 'rewardpierwebpush';

let _vertexModel = null;
function getVertexModel() {
  if (_vertexModel) return _vertexModel;
  const vertex = new VertexAI({ project: PROJECT_ID, location: 'us-central1' });
  _vertexModel = vertex.getGenerativeModel({
    model: 'gemini-2.5-flash-lite',
    generationConfig: { temperature: 0, maxOutputTokens: 8 },
  });
  return _vertexModel;
}

/**
 * Определяет пол по имени через Gemini. Кеш в memberships.userGender ('m'/'f'/'u').
 * Возвращает 'm' / 'f' / 'u' (unknown — будем использовать gender-neutral формулировку).
 * Gender нужен только для RU локали (русские глаголы прошедшего времени gendered).
 */
async function detectGender(name) {
  if (!name) return 'u';
  try {
    const model = getVertexModel();
    const prompt = `Определи пол по имени. Ответь одной буквой: m (мужчина), f (женщина), u (не уверен). Имя: "${name}"`;
    const resp = await model.generateContent(prompt);
    const text = resp.response?.candidates?.[0]?.content?.parts?.[0]?.text?.trim().toLowerCase() || '';
    if (text.startsWith('m')) return 'm';
    if (text.startsWith('f') || text.startsWith('ж')) return 'f';
    return 'u';
  } catch (e) {
    logger.warning(`detectGender failed for "${name}":`, e.message);
    return 'u';
  }
}

/**
 * Получить gender с кешем в memberships этого юзера.
 */
async function getOrComputeGender(db, authorUID, authorName) {
  if (!authorUID || !authorName) return 'u';
  const cached = await db.collection('memberships').where('userUID', '==', authorUID).limit(1).get();
  if (!cached.empty) {
    const g = cached.docs[0].data().userGender;
    if (g === 'm' || g === 'f' || g === 'u') return g;
  }
  const gender = await detectGender(authorName);
  if (!cached.empty) {
    const updates = [];
    const allMemberships = await db.collection('memberships').where('userUID', '==', authorUID).get();
    for (const m of allMemberships.docs) {
      updates.push(m.ref.update({ userGender: gender }).catch(() => {}));
    }
    await Promise.all(updates);
  }
  return gender;
}

/**
 * Читает per-user настройки получателя из users/{uid} одним GET:
 *  - locale (для языка body), fallback 'en'
 *  - pushEnabled (глобальный тоггл уведомлений), отсутствие поля → true
 */
async function getUserPrefs(db, uid) {
  try {
    const doc = await db.collection('users').doc(uid).get();
    const data = doc.exists ? (doc.data() || {}) : {};
    const locale = data.userLocale || 'en';
    const pushEnabled = data.pushEnabled !== false; // отсутствие/true → шлём
    return { locale, pushEnabled };
  } catch (_) {
    return { locale: 'en', pushEnabled: true };
  }
}

/**
 * Атомарно инкрементит users/{uid}.unreadCount и возвращает новое значение для badge.
 * Транзакция нужна т.к. несколько пушей одному юзеру могут прийти конкурентно.
 * При сбое — fallback badge=1 (лучше показать хоть что-то, чем уронить отправку).
 */
async function bumpUnread(db, uid) {
  const ref = db.collection('users').doc(uid);
  try {
    return await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = (snap.exists && typeof snap.data().unreadCount === 'number') ? snap.data().unreadCount : 0;
      const next = cur + 1;
      t.set(ref, { unreadCount: next }, { merge: true });
      return next;
    });
  } catch (e) {
    logger.warning(`bumpUnread failed for ${uid}: ${e.message}`);
    return 1;
  }
}

/**
 * Build push body на нужном языке. Russian — единственный gendered, остальные neutral verbs.
 *
 * Шаблоны:
 *   ru: "Влад добавил желание" / "Настя добавила желание" / "Алекс добавил(а) желание"
 *   en: "Vlad added a wish"
 *   ... (11 локалей)
 *
 * action: 'added' | 'updated' | 'deleted'
 */
function buildBody(authorName, gender, action, locale) {
  const name = authorName || null;

  switch (locale) {
    case 'ru': {
      const verbBase = action === 'added' ? 'добавил' : (action === 'deleted' ? 'удалил' : 'обновил');
      if (!name) return `Кто-то ${verbBase}(а) желание`;
      if (gender === 'm') return `${name} ${verbBase} желание`;
      if (gender === 'f') return `${name} ${verbBase}а желание`;
      return `${name} ${verbBase}(а) желание`;
    }
    case 'es': {
      const verb = action === 'added' ? 'añadió' : (action === 'deleted' ? 'eliminó' : 'actualizó');
      return name ? `${name} ${verb} un deseo` : `Alguien ${verb} un deseo`;
    }
    case 'de': {
      const verb = action === 'added' ? 'hat einen Wunsch hinzugefügt'
        : action === 'deleted' ? 'hat einen Wunsch gelöscht'
        : 'hat einen Wunsch aktualisiert';
      return name ? `${name} ${verb}` : `Jemand ${verb}`;
    }
    case 'fr': {
      const verb = action === 'added' ? 'a ajouté un vœu'
        : action === 'deleted' ? 'a supprimé un vœu'
        : 'a mis à jour un vœu';
      return name ? `${name} ${verb}` : `Quelqu'un ${verb}`;
    }
    case 'it': {
      const verb = action === 'added' ? 'ha aggiunto un desiderio'
        : action === 'deleted' ? 'ha eliminato un desiderio'
        : 'ha aggiornato un desiderio';
      return name ? `${name} ${verb}` : `Qualcuno ${verb}`;
    }
    case 'ja': {
      const verb = action === 'added' ? '希望を追加しました'
        : action === 'deleted' ? '希望を削除しました'
        : '希望を更新しました';
      return name ? `${name}さんが${verb}` : `誰かが${verb}`;
    }
    case 'zh-Hans': {
      const verb = action === 'added' ? '添加了一个心愿'
        : action === 'deleted' ? '删除了一个心愿'
        : '更新了一个心愿';
      return name ? `${name} ${verb}` : `有人${verb}`;
    }
    case 'ko': {
      const verb = action === 'added' ? '위시를 추가했어요'
        : action === 'deleted' ? '위시를 삭제했어요'
        : '위시를 업데이트했어요';
      return name ? `${name}님이 ${verb}` : `누군가 ${verb}`;
    }
    case 'pt-BR': {
      const verb = action === 'added' ? 'adicionou um desejo'
        : action === 'deleted' ? 'removeu um desejo'
        : 'atualizou um desejo';
      return name ? `${name} ${verb}` : `Alguém ${verb}`;
    }
    case 'en':
    default: {
      const verb = action === 'added' ? 'added a wish'
        : action === 'deleted' ? 'deleted a wish'
        : 'updated a wish';
      return name ? `${name} ${verb}` : `Someone ${verb}`;
    }
  }
}

/** bytesValue из Firestore приходит как Buffer — конвертим в base64-строку для FCM data. */
function bytesToBase64(v) {
  if (v == null) return null;
  if (Buffer.isBuffer(v)) return v.toString('base64');
  if (typeof v === 'string') return v; // на случай если уже строка
  try { return Buffer.from(v).toString('base64'); } catch (_) { return null; }
}

exports.onSharedItemWritten = onDocumentWritten(
  {
    document: 'shared_wishlists/{wishlistID}/items/{itemID}',
    region: REGION,
  },
  async (event) => {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    const wishlistID = event.params.wishlistID;
    const itemID = event.params.itemID;

    let action;
    if (!before && after) action = 'added';
    else if (before && !after) action = 'deleted';
    else if (before && after) action = 'updated';
    else return;

    // SKIP push при update без изменения зашифрованного контента: reorder (только sortIndex),
    // archive-toggle (только isArchived), смена lastModifiedByUID, обновление updatedAt.
    // encryptedPayload идентичен → реального контентного изменения не было → пуш не нужен.
    if (action === 'updated' && before && after) {
      // Lossless сравнение бинарного ciphertext. Buffer.toString() по умолчанию UTF-8 — лоссив на
      // произвольных байтах (U+FFFD коллизии), поэтому сравниваем .equals() / base64, не raw toString().
      const bEnc = before.encryptedPayload;
      const aEnc = after.encryptedPayload;
      const unchanged = (Buffer.isBuffer(bEnc) && Buffer.isBuffer(aEnc))
        ? bEnc.equals(aEnc)
        : (bEnc?.toString('base64') === aEnc?.toString('base64'));
      if (unchanged) {
        logger.debug(`Skipping no-content-change for ${wishlistID}/${itemID} (reorder/archive/stamp)`);
        return;
      }
    }

    const db = admin.firestore();
    const lastModifiedByUID = (after?.lastModifiedByUID || before?.lastModifiedByUID || null);

    // Короткое зашифрованное имя желания для NSE (если клиент его записал). Сервер расшифровать не может.
    const encryptedNameB64 = bytesToBase64(after?.encryptedName ?? before?.encryptedName ?? null);

    // 1. Memberships → recipients (+ per-list notification preference из самого membership-документа).
    const membersSnap = await db.collection('memberships')
      .where('wishlistID', '==', wishlistID)
      .get();

    const recipients = [];
    let authorName = null;
    for (const doc of membersSnap.docs) {
      const m = doc.data();
      if (!m.userUID) continue;
      if (lastModifiedByUID && m.userUID === lastModifiedByUID) {
        authorName = m.userName || null;
        continue;
      }
      // Per-list тоггл: отсутствие поля → true (без регресса для старых memberships).
      if (m.notificationsEnabled === false) continue;
      recipients.push({ uid: m.userUID, userName: m.userName });
    }

    if (recipients.length === 0) {
      logger.info(`No recipients for ${wishlistID}/${itemID}`);
      return;
    }

    // 2. Per-recipient: prefs (locale + global pushEnabled) + FCM tokens.
    const resolved = await Promise.all(recipients.map(async (r) => {
      const [tokensSnap, prefs] = await Promise.all([
        db.collection('users').doc(r.uid).collection('fcmTokens').get(),
        getUserPrefs(db, r.uid),
      ]);
      if (!prefs.pushEnabled) return null; // глобальный тоггл выключен
      const tokens = [];
      for (const tDoc of tokensSnap.docs) {
        const t = tDoc.data();
        if (t.token) tokens.push({ token: t.token, uid: r.uid, hash: tDoc.id });
      }
      if (tokens.length === 0) return null;
      return { uid: r.uid, locale: prefs.locale, tokens };
    }));
    const activeRecipients = resolved.filter(Boolean);

    if (activeRecipients.length === 0) {
      logger.info(`No deliverable recipients for ${wishlistID}/${itemID} (tokens/prefs)`);
      return;
    }

    // 3. Gender (только если есть хоть один ru-получатель).
    let gender = 'u';
    if (activeRecipients.some(r => r.locale === 'ru')) {
      try {
        gender = await getOrComputeGender(db, lastModifiedByUID, authorName);
      } catch (e) {
        logger.warning('Gender detection failed, using neutral form:', e.message);
      }
    }

    // 4. Per-user send (badge персональный → нельзя один multicast на всех).
    let totalSent = 0, totalFailed = 0;
    const allStale = [];

    await Promise.all(activeRecipients.map(async (r) => {
      const badge = await bumpUnread(db, r.uid);
      const body = buildBody(authorName, gender, action, r.locale);
      const data = {
        type: 'wishlist_item_' + action,
        wishlistID,
        itemID,
      };
      if (encryptedNameB64) data.encryptedName = encryptedNameB64;

      const message = {
        notification: { title: 'I Wish', body },
        data,
        apns: {
          payload: { aps: { sound: 'default', badge, 'mutable-content': 1 } },
        },
        tokens: r.tokens.map(t => t.token),
      };

      try {
        const result = await admin.messaging().sendEachForMulticast(message);
        totalSent += result.successCount;
        totalFailed += result.failureCount;
        if (result.failureCount > 0) {
          result.responses.forEach((res, idx) => {
            if (!res.success && res.error) {
              const code = res.error.code;
              if (code === 'messaging/registration-token-not-registered' ||
                  code === 'messaging/invalid-registration-token') {
                allStale.push(r.tokens[idx]);
              }
            }
          });
        }
      } catch (err) {
        logger.error(`FCM send failed for uid=${r.uid}`, err);
      }
    }));

    logger.info(`Sent ${totalSent} pushes (failed ${totalFailed}) for ${wishlistID}/${itemID} (action=${action}, recipients=${activeRecipients.length})`);

    // Cleanup stale FCM tokens.
    for (const s of allStale) {
      await db.collection('users').doc(s.uid).collection('fcmTokens').doc(s.hash).delete().catch(() => {});
      logger.info(`Deleted stale FCM token uid=${s.uid} hash=${s.hash}`);
    }
  }
);
