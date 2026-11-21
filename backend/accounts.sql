-- PostgreSQL schema for the Vercel accounts service.

CREATE TABLE IF NOT EXISTS roam_accounts (
 id uuid PRIMARY KEY, email text UNIQUE NOT NULL, username text NOT NULL,
 tiktok text NOT NULL DEFAULT '', instagram text NOT NULL DEFAULT '',
 salt text NOT NULL, hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS roam_sessions (
 digest text PRIMARY KEY, account_id uuid REFERENCES roam_accounts(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS roam_messages (
 id uuid PRIMARY KEY, recipient_id uuid NOT NULL REFERENCES roam_accounts(id) ON DELETE CASCADE,
 body text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS roam_message_recipient ON roam_messages(recipient_id,created_at DESC);
CREATE TABLE IF NOT EXISTS roam_limits (bucket text NOT NULL,window_id bigint NOT NULL,count int NOT NULL,PRIMARY KEY(bucket,window_id));
