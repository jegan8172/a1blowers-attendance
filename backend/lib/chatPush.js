'use strict';

const https = require('https');

// Configure FCM_SERVER_KEY in the deployment environment. Until it is set,
// chat delivery continues normally without background notifications.
async function notifyConversation(db, conversationId, senderId, title, body) {
  const key = process.env.FCM_SERVER_KEY;
  if (!key) return;
  const [rows] = await db.query(`SELECT token FROM chat_push_tokens t JOIN chat_participants p ON p.user_id=t.user_id WHERE p.conversation_id=? AND p.user_id<>? AND (p.muted_until IS NULL OR p.muted_until<CURRENT_TIMESTAMP)`, [conversationId, senderId || 0]);
  await Promise.all(rows.map(({ token }) => new Promise((resolve) => {
    const request = https.request('https://fcm.googleapis.com/fcm/send', { method: 'POST', headers: { Authorization: `key=${key}`, 'Content-Type': 'application/json' } }, resolve);
    request.on('error', resolve);
    request.end(JSON.stringify({ to: token, notification: { title, body }, data: { conversationId: String(conversationId) } }));
  })));
}

module.exports = { notifyConversation };
