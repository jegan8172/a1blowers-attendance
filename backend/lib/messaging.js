'use strict';

const staff = require('./staffDirectory');
const chatPush = require('./chatPush');

function directKey(a, b) { return [Number(a), Number(b)].sort((x, y) => x - y).join(':'); }
function parseJson(value) { try { return value ? JSON.parse(value) : null; } catch (_) { return null; } }

async function directConversation(db, firstUserId, secondUserId) {
  const key = directKey(firstUserId, secondUserId);
  await db.query('INSERT IGNORE INTO chat_conversations (kind, direct_key) VALUES (\'direct\', ?)', [key]);
  const [[conversation]] = await db.query('SELECT id FROM chat_conversations WHERE direct_key = ? LIMIT 1', [key]);
  await db.query('INSERT IGNORE INTO chat_participants (conversation_id, user_id) VALUES (?, ?), (?, ?)', [conversation.id, firstUserId, conversation.id, secondUserId]);
  return conversation.id;
}

async function userIsActive(db, userId) {
  const user = await staff.findStaffById(db, userId);
  return user && Number(user.is_active) === 1 ? user : null;
}

async function isParticipant(db, conversationId, userId) {
  const [[row]] = await db.query('SELECT 1 AS ok FROM chat_participants WHERE conversation_id=? AND user_id=?', [conversationId, userId]);
  return Boolean(row);
}

async function addMessage(db, { conversationId, senderUserId = null, kind = 'text', body = null, eventType = null, payload = null }) {
  const [result] = await db.query(
    'INSERT INTO chat_messages (conversation_id,sender_user_id,message_kind,body,event_type,event_payload) VALUES (?,?,?,?,?,?)',
    [conversationId, senderUserId, kind, body, eventType, payload ? JSON.stringify(payload) : null]
  );
  await db.query('UPDATE chat_conversations SET updated_at=CURRENT_TIMESTAMP WHERE id=?', [conversationId]);
  return result.insertId;
}

async function messageFor(db, messageId) {
  const [[message]] = await db.query(
    `SELECT m.id,m.conversation_id,m.sender_user_id,m.message_kind,m.body,m.event_type,m.event_payload,m.created_at,
      s.full_name AS sender_name FROM chat_messages m LEFT JOIN ${staff.staffFrom()} s ON s.${staff.quote(staff.STAFF.id)}=m.sender_user_id WHERE m.id=?`, [messageId]);
  if (!message) return null;
  message.event_payload = parseJson(message.event_payload);
  return message;
}

async function createAttendanceSystemCards(db, { employeeId, attendanceDate, eventType, eventKey, body, payload }) {
  const [event] = await db.query('INSERT IGNORE INTO attendance_message_events (employee_id,attendance_date,event_type,event_key) VALUES (?,?,?,?)', [employeeId, attendanceDate, eventType, eventKey]);
  if (!event.affectedRows) return [];
  const [admins] = await db.query(`SELECT ${staff.quote(staff.STAFF.id)} AS id FROM ${staff.staffFrom()} WHERE ${staff.quote(staff.STAFF.active)}=1 AND LOWER(user_type)='admin'`);
  const created = [];
  for (const admin of admins) {
    const conversationId = await directConversation(db, employeeId, admin.id);
    const id = await addMessage(db, { conversationId, kind: 'system', body, eventType, payload });
    created.push(await messageFor(db, id));
  }
  return created;
}

async function emitMessages(io, db, messages) {
  for (const message of messages) {
    if (!message) continue;
    if (io) io.to(`conversation:${message.conversation_id}`).emit('chat:message', message);
    const [participants] = await db.query('SELECT user_id FROM chat_participants WHERE conversation_id=?', [message.conversation_id]);
    if (io) for (const participant of participants) io.to(`user:${participant.user_id}`).emit('chat:message', message);
    const isAttendanceUpdate = message.message_kind === 'system';
    const title = isAttendanceUpdate
      ? 'Attendance update'
      : message.message_kind === 'attachment' ? 'New attachment' : 'New message';
    chatPush.notifyConversation(
      db,
      message.conversation_id,
      message.sender_user_id,
      title,
      message.body || title,
      isAttendanceUpdate ? 'attendance_update' : 'chat_message'
    ).catch(() => {});
  }
}

module.exports = { directConversation, userIsActive, isParticipant, addMessage, messageFor, createAttendanceSystemCards, emitMessages };
