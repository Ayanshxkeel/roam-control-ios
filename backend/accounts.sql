-- PostgreSQL schema for the Vercel accounts service.

CREATE TABLE IF NOT EXISTS roam_accounts (
 id uuid PRIMARY KEY, email text UNIQUE NOT NULL, username text NOT NULL,
 tiktok text NOT NULL DEFAULT '', instagram text NOT NULL DEFAULT '',
 salt text NOT NULL, hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS referral_source text NOT NULL DEFAULT '';
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS referral_handle text NOT NULL DEFAULT '';
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS profile_photo text NOT NULL DEFAULT '';
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS share_location boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS last_seen timestamptz;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS app_active boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS latitude double precision;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS longitude double precision;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS is_spoofing boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS location_updated_at timestamptz;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS community_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS community_blocked boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS community_keep_for_owner boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS roam_sessions (
 digest text PRIMARY KEY, account_id uuid REFERENCES roam_accounts(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS roam_messages (
 id uuid PRIMARY KEY, recipient_id uuid NOT NULL REFERENCES roam_accounts(id) ON DELETE CASCADE,
 body text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS roam_broadcasts (id uuid PRIMARY KEY, body text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE roam_messages ADD COLUMN IF NOT EXISTS broadcast_id uuid REFERENCES roam_broadcasts(id);
CREATE UNIQUE INDEX IF NOT EXISTS roam_broadcast_recipient ON roam_messages(broadcast_id,recipient_id);
CREATE INDEX IF NOT EXISTS roam_message_recipient ON roam_messages(recipient_id,created_at DESC);
CREATE TABLE IF NOT EXISTS roam_limits (bucket text NOT NULL,window_id bigint NOT NULL,count int NOT NULL,PRIMARY KEY(bucket,window_id));
