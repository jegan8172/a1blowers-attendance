'use strict';

const { getMessaging } = require('./firebaseAdmin');

const INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered'
]);

function logFailure(message, details) {
  // Keep operational diagnostics useful without ever printing tokens or keys.
  console.warn(`Chat push ${message}`, details);
}

async function removeInvalidTokens(db, responses, tokens) {
  const invalid = [];
  responses.forEach((response, index) => {
    if (!response.success && INVALID_TOKEN_CODES.has(response.error?.code)) invalid.push(tokens[index]);
  });
  if (!invalid.length) return;
  await Promise.all(invalid.map((token) => db.query('DELETE FROM chat_push_tokens WHERE token=?', [token])));
  console.info(`Removed ${invalid.length} invalid chat push token(s).`);
}

// This is deliberately best-effort: FCM failures must never interrupt chat or attendance writes.
async function notifyConversation(db, conversationId, senderId, title, body, type = 'chat_message') {
  try {
    const messaging = getMessaging();
    if (!messaging) return { sent: 0, disabled: true };
    const [rows] = await db.query(
      `SELECT DISTINCT t.token FROM chat_push_tokens t JOIN chat_participants p ON p.user_id=t.user_id
       WHERE p.conversation_id=? AND p.user_id<>? AND (p.muted_until IS NULL OR p.muted_until<CURRENT_TIMESTAMP)`,
      [conversationId, senderId || 0]
    );
    const tokens = rows.map((row) => row.token).filter(Boolean);
    if (!tokens.length) return { sent: 0 };
    let successCount = 0;
    for (let start = 0; start < tokens.length; start += 500) {
      const batch = tokens.slice(start, start + 500);
      const response = await messaging.sendEachForMulticast({
        tokens: batch,
        notification: { title: String(title || 'GoDigital Attendance'), body: String(body || '') },
        data: { conversationId: String(conversationId), type: String(type) },
        android: { priority: 'high', notification: { channelId: 'chat_messages' } },
        webpush: { headers: { Urgency: 'high' } }
      });
      successCount += response.successCount;
      await removeInvalidTokens(db, response.responses, batch);
      if (response.failureCount) logFailure('delivery batch had failures.', { conversationId, failed: response.failureCount });
    }
    return { sent: successCount };
  } catch (error) {
    logFailure('delivery failed.', { conversationId, code: error?.code, message: error?.message });
    return { sent: 0, failed: true };
  }
}

module.exports = { notifyConversation, INVALID_TOKEN_CODES };
