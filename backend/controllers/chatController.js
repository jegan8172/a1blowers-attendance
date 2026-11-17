'use strict';

const db = require('../config/db');
const staff = require('../lib/staffDirectory');
const chat = require('../lib/messaging');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const TEXT_LIMIT = 4000;
function ok(res, data, message) { return res.json({ success: true, message, data }); }
function fail(res, status, message) { return res.status(status).json({ success: false, message }); }
function asId(value) { const id = Number(value); return Number.isInteger(id) && id > 0 ? id : null; }
function isAdmin(req) { return String(req.user && req.user.userType).toLowerCase() === 'admin'; }
async function roleFor(conversationId, userId) { const [[row]] = await db.query('SELECT member_role FROM chat_participants WHERE conversation_id=? AND user_id=?', [conversationId, userId]); return row && row.member_role; }
async function canManage(conversationId, req) { return isAdmin(req) || ['owner', 'admin'].includes(await roleFor(conversationId, req.user.id)); }

async function listPeople(req, res) {
  try {
    const people = await staff.listActiveStaff(db);
    return ok(res, people.filter(p => Number(p.id) !== Number(req.user.id)).map(p => ({ id: p.id, name: p.full_name, role: p.role })), 'People loaded');
  } catch (error) { return fail(res, 500, error.message); }
}

async function openDirect(req, res) {
  try {
    const otherUserId = asId(req.body && req.body.userId);
    if (!otherUserId || otherUserId === Number(req.user.id)) return fail(res, 400, 'Choose another active user.');
    if (!await chat.userIsActive(db, otherUserId)) return fail(res, 404, 'User not found or inactive.');
    const conversationId = await chat.directConversation(db, req.user.id, otherUserId);
    return ok(res, { id: conversationId }, 'Conversation ready');
  } catch (error) { return fail(res, 500, error.message); }
}

async function createGroup(req, res) {
  try {
    const name = String(req.body && req.body.name || '').trim();
    const memberIds = [...new Set([req.user.id, ...((req.body && req.body.memberIds) || []).map(asId).filter(Boolean)])];
    if (!name || name.length > 120 || memberIds.length < 2) return fail(res, 400, 'Enter a group name and at least one member.');
    for (const userId of memberIds) if (!await chat.userIsActive(db, userId)) return fail(res, 404, 'A selected member is inactive.');
    const [result] = await db.query("INSERT INTO chat_conversations (kind,direct_key,group_name,created_by) VALUES ('group',NULL,?,?)", [name, req.user.id]);
    for (const userId of memberIds) await db.query('INSERT INTO chat_participants (conversation_id,user_id,member_role) VALUES (?,?,?)', [result.insertId, userId, userId === req.user.id ? 'owner' : 'member']);
    return ok(res, { id: result.insertId, name }, 'Group created');
  } catch (error) { return fail(res, 500, error.message); }
}

async function listConversations(req, res) {
  try {
    const [rows] = await db.query(
      `SELECT c.id,c.kind AS conversation_type,c.group_name,c.updated_at, p.muted_until, other.id AS other_user_id, COALESCE(c.group_name,other.full_name) AS other_name, other.role AS other_role, presence.last_seen_at,
       (SELECT body FROM chat_messages WHERE conversation_id=c.id ORDER BY id DESC LIMIT 1) AS latest_body,
       (SELECT message_kind FROM chat_messages WHERE conversation_id=c.id ORDER BY id DESC LIMIT 1) AS latest_kind,
       (SELECT COUNT(*) FROM chat_messages m WHERE m.conversation_id=c.id AND m.id > COALESCE(p.last_read_message_id,0)) AS unread_count
       FROM chat_participants p JOIN chat_conversations c ON c.id=p.conversation_id
       LEFT JOIN chat_participants op ON op.conversation_id=c.id AND op.user_id<>p.user_id AND c.kind='direct'
       LEFT JOIN ${staff.staffFrom()} other ON other.${staff.quote(staff.STAFF.id)}=op.user_id
       LEFT JOIN chat_user_presence presence ON presence.user_id=op.user_id
       WHERE p.user_id=? ORDER BY c.updated_at DESC`, [req.user.id]);
    return ok(res, rows, 'Conversations loaded');
  } catch (error) { return fail(res, 500, error.message); }
}

async function messages(req, res) {
  try {
    const conversationId = asId(req.params.id); const before = asId(req.query.before) || 0;
    if (!conversationId || !await chat.isParticipant(db, conversationId, req.user.id)) return fail(res, 404, 'Conversation not found');
    const args = [conversationId]; let older = '';
    if (before) { older = ' AND m.id < ?'; args.push(before); }
    args.push(51);
    const [rows] = await db.query(
      `SELECT m.id,m.conversation_id,m.sender_user_id,m.message_kind,m.body,m.event_type,m.event_payload,m.created_at,s.full_name AS sender_name,
       COALESCE((SELECT MIN(other_participant.last_read_message_id)
        FROM chat_participants other_participant
        WHERE other_participant.conversation_id=m.conversation_id
          AND other_participant.user_id<>m.sender_user_id), 0) AS recipient_last_read_message_id
       FROM chat_messages m LEFT JOIN ${staff.staffFrom()} s ON s.${staff.quote(staff.STAFF.id)}=m.sender_user_id
       WHERE m.conversation_id=?${older} ORDER BY m.id DESC LIMIT ?`, args);
    const sliced = rows.slice(0, 50).reverse().map(r => ({
      ...r,
      event_payload: r.event_payload ? JSON.parse(r.event_payload) : null,
      delivery_status: r.sender_user_id === Number(req.user.id)
        ? (Number(r.recipient_last_read_message_id) >= Number(r.id) ? 'read' : 'sent')
        : null
    }));
    for (const message of sliced) {
      const [attachments] = await db.query('SELECT id,storage_key,original_name,content_type,byte_size FROM chat_attachments WHERE message_id=?', [message.id]);
      message.attachments = attachments.map(item => ({ ...item, url: item.storage_key }));
    }
    return ok(res, { items: sliced, hasMore: rows.length > 50 }, 'Messages loaded');
  } catch (error) { return fail(res, 500, error.message); }
}

async function attachments(req, res) {
  try {
    const conversationId = asId(req.params.id);
    if (!conversationId || !await chat.isParticipant(db, conversationId, req.user.id)) return fail(res, 404, 'Conversation not found');
    const [rows] = await db.query(
      `SELECT a.id,a.storage_key,a.original_name,a.content_type,a.byte_size,a.created_at,m.id AS message_id,m.sender_user_id
       FROM chat_attachments a JOIN chat_messages m ON m.id=a.message_id
       WHERE m.conversation_id=? ORDER BY a.created_at DESC`,
      [conversationId]
    );
    return ok(res, rows.map(item => ({ ...item, url: item.storage_key })), 'Attachments loaded');
  } catch (error) { return fail(res, 500, error.message); }
}

async function search(req, res) {
  try {
    const conversationId = asId(req.params.id); const query = String(req.query.q || '').trim();
    if (!conversationId || !await chat.isParticipant(db, conversationId, req.user.id)) return fail(res, 404, 'Conversation not found');
    if (!query || query.length > 120) return fail(res, 400, 'Enter a search term.');
    const [rows] = await db.query(`SELECT m.id,m.sender_user_id,m.body,m.message_kind,m.created_at FROM chat_messages m LEFT JOIN chat_attachments a ON a.message_id=m.id WHERE m.conversation_id=? AND (m.body LIKE ? OR a.original_name LIKE ?) GROUP BY m.id ORDER BY m.id DESC LIMIT 50`, [conversationId, `%${query}%`, `%${query}%`]);
    return ok(res, rows, 'Search complete');
  } catch (error) { return fail(res, 500, error.message); }
}

async function pins(req, res) {
  try { const conversationId = asId(req.params.id); if (!conversationId || !await chat.isParticipant(db, conversationId, req.user.id)) return fail(res, 404, 'Conversation not found'); const [rows] = await db.query('SELECT p.created_at AS pinned_at,p.pinned_by,m.id,m.body,m.message_kind,m.created_at FROM chat_message_pins p JOIN chat_messages m ON m.id=p.message_id WHERE p.conversation_id=? ORDER BY p.created_at DESC', [conversationId]); return ok(res, rows, 'Pins loaded'); } catch (error) { return fail(res, 500, error.message); }
}

async function pin(req, res) {
  try { const conversationId=asId(req.params.id), messageId=asId(req.params.messageId); if(!conversationId||!messageId||!await chat.isParticipant(db,conversationId,req.user.id)) return fail(res,404,'Conversation not found'); const [[conversation]]=await db.query('SELECT kind FROM chat_conversations WHERE id=?',[conversationId]); if(conversation.kind==='group'&&!await canManage(conversationId,req)) return fail(res,403,'Only group owners or admins can pin messages'); const [[message]]=await db.query('SELECT id FROM chat_messages WHERE id=? AND conversation_id=?',[messageId,conversationId]); if(!message)return fail(res,404,'Message not found'); await db.query('INSERT IGNORE INTO chat_message_pins (message_id,conversation_id,pinned_by) VALUES (?,?,?)',[messageId,conversationId,req.user.id]); return ok(res,{},'Message pinned'); } catch(error){return fail(res,500,error.message);}
}

async function unpin(req, res) { try { const conversationId=asId(req.params.id),messageId=asId(req.params.messageId); if(!conversationId||!messageId||!await chat.isParticipant(db,conversationId,req.user.id))return fail(res,404,'Conversation not found'); const [[conversation]]=await db.query('SELECT kind FROM chat_conversations WHERE id=?',[conversationId]); if(conversation.kind==='group'&&!await canManage(conversationId,req))return fail(res,403,'Only group owners or admins can unpin messages'); await db.query('DELETE FROM chat_message_pins WHERE conversation_id=? AND message_id=?',[conversationId,messageId]);return ok(res,{},'Message unpinned'); }catch(error){return fail(res,500,error.message);} }

async function markDelivered(req,res){try{const conversationId=asId(req.params.id),messageId=asId(req.body&&req.body.messageId);if(!conversationId||!messageId||!await chat.isParticipant(db,conversationId,req.user.id))return fail(res,404,'Conversation not found');await db.query('UPDATE chat_participants SET last_delivered_message_id=GREATEST(COALESCE(last_delivered_message_id,0),?) WHERE conversation_id=? AND user_id=?',[messageId,conversationId,req.user.id]);req.app.get('io')?.to(`conversation:${conversationId}`).emit('chat:delivered',{conversationId,userId:req.user.id,messageId});return ok(res,{},'Delivery confirmed');}catch(error){return fail(res,500,error.message);}}

async function dial(req,res){try{const conversationId=asId(req.params.id);if(!conversationId||!await chat.isParticipant(db,conversationId,req.user.id))return fail(res,404,'Conversation not found');const [[row]]=await db.query('SELECT profile.phone FROM chat_participants participant JOIN hrms_employee_profiles profile ON profile.employee_user_id=participant.user_id WHERE participant.conversation_id=? AND participant.user_id<>? LIMIT 1',[conversationId,req.user.id]);return ok(res,{phone:row&&row.phone||''},'Dial contact loaded');}catch(error){return fail(res,500,error.message);}}

async function attendanceSummary(req,res){try{const conversationId=asId(req.params.id);if(!conversationId||!await chat.isParticipant(db,conversationId,req.user.id))return fail(res,404,'Conversation not found');const [[other]]=await db.query('SELECT user_id FROM chat_participants WHERE conversation_id=? AND user_id<>? LIMIT 1',[conversationId,req.user.id]);const employeeId=other&&other.user_id;if(!employeeId)return fail(res,404,'Employee not found');if(!isAdmin(req)&&employeeId!==Number(req.user.id))return fail(res,403,'Not authorized to view this attendance summary');const [rows]=await db.query("SELECT SUM(attendance_status='present') present_days,SUM(is_late=1) late_arrivals,SUM(attendance_status IN ('on_leave','half_leave')) leave_days FROM attendance_records WHERE employee_id=? AND YEAR(attendance_date)=YEAR(CURDATE()) AND MONTH(attendance_date)=MONTH(CURDATE())",[employeeId]);const [[pay]]=await db.query('SELECT net_pay FROM hrms_payroll_items WHERE employee_id=? AND pay_year=YEAR(CURDATE()) AND pay_month=MONTH(CURDATE()) ORDER BY id DESC LIMIT 1',[employeeId]);return ok(res,{...rows[0],net_earned:Number(pay&&pay.net_pay||0)},'Attendance summary loaded');}catch(error){return fail(res,500,error.message);}}

async function uploadAttachment(req, res) {
  try {
    const conversationId = asId(req.params.id); const file = req.file;
    if (!conversationId || !await chat.isParticipant(db, conversationId, req.user.id)) return fail(res, 404, 'Conversation not found');
    if (!file) return fail(res, 400, 'Choose a file to attach.');
    const allowed = /^(image\/(jpeg|png|heic|webp)|audio\/(mpeg|wav|mp4|x-m4a)|application\/(pdf|vnd\.openxmlformats-officedocument\.(wordprocessingml\.document|spreadsheetml\.sheet|presentationml\.presentation)))$/;
    if (!allowed.test(file.mimetype)) return fail(res, 400, 'Only images, audio, PDF, DOCX, XLSX, and PPTX files are allowed.');
    const folder = path.join(__dirname, '..', 'uploads', 'chat'); fs.mkdirSync(folder, { recursive: true });
    const extension = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '');
    const filename = `${crypto.randomUUID()}${extension}`; fs.writeFileSync(path.join(folder, filename), file.buffer);
    const messageId = await chat.addMessage(db, { conversationId, senderUserId: req.user.id, kind: 'attachment', body: file.originalname });
    const storageKey = `/uploads/chat/${filename}`;
    await db.query('INSERT INTO chat_attachments (message_id,storage_key,original_name,content_type,byte_size) VALUES (?,?,?,?,?)', [messageId, storageKey, file.originalname, file.mimetype, file.size]);
    const message = await chat.messageFor(db, messageId); message.attachments = [{ storage_key: storageKey, original_name: file.originalname, content_type: file.mimetype, byte_size: file.size, url: storageKey }];
    await chat.emitMessages(req.app.get('io'), db, [message]);
    return ok(res, message, 'Attachment sent');
  } catch (error) { return fail(res, 500, error.message); }
}

async function send(req, res) {
  try {
    const conversationId = asId(req.params.id); const body = String(req.body && req.body.body || '').trim();
    if (!conversationId || !await chat.isParticipant(db, conversationId, req.user.id)) return fail(res, 404, 'Conversation not found');
    if (!body || body.length > TEXT_LIMIT) return fail(res, 400, `Message must be between 1 and ${TEXT_LIMIT} characters.`);
    const id = await chat.addMessage(db, { conversationId, senderUserId: req.user.id, body });
    const message = await chat.messageFor(db, id);
    await chat.emitMessages(req.app.get('io'), db, [message]);
    return ok(res, message, 'Message sent');
  } catch (error) { return fail(res, 500, error.message); }
}

async function markRead(req, res) {
  try {
    const conversationId = asId(req.params.id); const messageId = asId(req.body && req.body.messageId);
    if (!conversationId || !messageId || !await chat.isParticipant(db, conversationId, req.user.id)) return fail(res, 404, 'Conversation not found');
    await db.query('UPDATE chat_participants SET last_read_message_id=GREATEST(COALESCE(last_read_message_id,0),?) WHERE conversation_id=? AND user_id=?', [messageId, conversationId, req.user.id]);
    req.app.get('io')?.to(`conversation:${conversationId}`).emit('chat:read', { conversationId, userId: req.user.id, messageId });
    return ok(res, {}, 'Conversation marked read');
  } catch (error) { return fail(res, 500, error.message); }
}

async function mute(req, res) {
  try {
    const conversationId = asId(req.params.id); const minutes = Number(req.body && req.body.minutes || 0);
    if (!conversationId || !await chat.isParticipant(db, conversationId, req.user.id)) return fail(res, 404, 'Conversation not found');
    if (!Number.isInteger(minutes) || minutes < 0 || minutes > 43200) return fail(res, 400, 'Invalid mute duration');
    await db.query('UPDATE chat_participants SET muted_until=? WHERE conversation_id=? AND user_id=?', [minutes ? new Date(Date.now() + minutes * 60000) : null, conversationId, req.user.id]);
    return ok(res, {}, 'Mute preference updated');
  } catch (error) { return fail(res, 500, error.message); }
}

async function registerPushToken(req, res) {
  try {
    const token = String(req.body && req.body.token || '').trim(); const platform = String(req.body && req.body.platform || '').toLowerCase();
    if (!token || token.length > 512 || !['android', 'ios', 'web'].includes(platform)) return fail(res, 400, 'Valid push token and platform required');
    await db.query('INSERT INTO chat_push_tokens (user_id,token,platform) VALUES (?,?,?) ON DUPLICATE KEY UPDATE user_id=VALUES(user_id),platform=VALUES(platform),updated_at=CURRENT_TIMESTAMP', [req.user.id, token, platform]);
    return ok(res, {}, 'Push device registered');
  } catch (error) { return fail(res, 500, error.message); }
}

module.exports = { listPeople, openDirect, createGroup, listConversations, messages, search, pins, pin, unpin, attachments, attendanceSummary, dial, markDelivered, uploadAttachment, send, markRead, mute, registerPushToken };
