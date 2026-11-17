'use strict';

// Kept separate from the attendance schema so messaging can evolve without
// coupling its data lifecycle to payroll or clock-log migrations.
async function ensureMessagingTables(db) {
  const statements = [
    `CREATE TABLE IF NOT EXISTS chat_conversations (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      kind ENUM('direct') NOT NULL DEFAULT 'direct',
      direct_key VARCHAR(64) NOT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uq_chat_direct_key (direct_key), KEY idx_chat_updated (updated_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS chat_participants (
      conversation_id BIGINT UNSIGNED NOT NULL, user_id INT NOT NULL,
      last_read_message_id BIGINT UNSIGNED NULL, muted_until DATETIME NULL,
      joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (conversation_id, user_id), KEY idx_chat_participant_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS chat_messages (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      conversation_id BIGINT UNSIGNED NOT NULL, sender_user_id INT NULL,
      message_kind ENUM('text','system','attachment') NOT NULL DEFAULT 'text',
      body TEXT NULL, event_type VARCHAR(80) NULL, event_payload JSON NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      KEY idx_chat_message_conversation (conversation_id, id), KEY idx_chat_message_sender (sender_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS chat_attachments (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      message_id BIGINT UNSIGNED NOT NULL, storage_key VARCHAR(512) NOT NULL,
      original_name VARCHAR(255) NOT NULL, content_type VARCHAR(160) NOT NULL,
      byte_size INT UNSIGNED NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      KEY idx_chat_attachment_message (message_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS chat_push_tokens (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL,
      token VARCHAR(512) NOT NULL, platform ENUM('android','web') NOT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uq_chat_push_token (token(255)), KEY idx_chat_push_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS attendance_message_events (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL,
      attendance_date DATE NOT NULL, event_type VARCHAR(80) NOT NULL,
      event_key VARCHAR(128) NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_attendance_message_event (employee_id, event_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`
  ];
  for (const statement of statements) await db.query(statement);
  // Existing installations started as direct-chat only; evolve them in place.
  await db.query("ALTER TABLE chat_conversations MODIFY kind VARCHAR(16) NOT NULL DEFAULT 'direct'");
  await db.query('ALTER TABLE chat_conversations MODIFY direct_key VARCHAR(64) NULL');
  for (const sql of [
    'ALTER TABLE chat_conversations ADD COLUMN group_name VARCHAR(120) NULL',
    'ALTER TABLE chat_conversations ADD COLUMN created_by INT NULL',
    "ALTER TABLE chat_participants ADD COLUMN member_role VARCHAR(16) NOT NULL DEFAULT 'member'",
    'ALTER TABLE chat_participants ADD COLUMN last_delivered_message_id BIGINT UNSIGNED NULL'
  ]) {
    try { await db.query(sql); } catch (error) { if (error.code !== 'ER_DUP_FIELDNAME') throw error; }
  }
  for (const statement of [
    `CREATE TABLE IF NOT EXISTS chat_message_pins (
      message_id BIGINT UNSIGNED NOT NULL, conversation_id BIGINT UNSIGNED NOT NULL,
      pinned_by INT NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY(message_id), KEY idx_chat_pin_conversation(conversation_id,created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS chat_user_presence (
      user_id INT NOT NULL PRIMARY KEY, last_seen_at DATETIME NULL,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`
  ]) await db.query(statement);
}

module.exports = { ensureMessagingTables };
