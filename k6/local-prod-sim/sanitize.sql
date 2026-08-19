\set ON_ERROR_STOP on

BEGIN;

DELETE FROM inbox_delivery_outbox;
DELETE FROM inbox_alerts;
DELETE FROM race_resolution_delivery_intents;
DELETE FROM race_resolution_post_tasks;
DELETE FROM race_resolution_jobs_v2;
DELETE FROM race_resolution_jobs;
DELETE FROM device_tokens;
DELETE FROM notifications;
DELETE FROM feedback_messages;
DELETE FROM feedback_threads;
DELETE FROM suggestions;
DELETE FROM android_waitlist_entries;
DELETE FROM link_opens;
DELETE FROM activation_events;

WITH ranked AS (
  SELECT id, row_number() OVER (ORDER BY id) AS n FROM users
)
UPDATE users AS u
SET apple_id = NULL,
    google_sub = NULL,
    email = 'capacity+' || ranked.n || '@example.invalid',
    name = 'Capacity User ' || ranked.n,
    display_name = 'capacity_user_' || ranked.n,
    first_name = 'Capacity',
    last_name = 'User ' || ranked.n,
    discoverable_name_search = 'capacity user ' || ranked.n,
    profile_photo_url = NULL,
    profile_photo_key = NULL,
    referral_code = 'cap' || lpad(ranked.n::text, 8, '0'),
    referred_by_code = NULL
FROM ranked
WHERE u.id = ranked.id;

WITH ranked AS (
  SELECT id, row_number() OVER (ORDER BY id) AS n FROM races
)
UPDATE races AS r
SET name = 'Capacity Race ' || ranked.n,
    share_token = CASE WHEN r.share_token IS NULL THEN NULL ELSE 'capacity-race-' || r.id END,
    team_a_name = CASE WHEN r.team_a_name IS NULL THEN NULL ELSE 'Capacity Team A' END,
    team_b_name = CASE WHEN r.team_b_name IS NULL THEN NULL ELSE 'Capacity Team B' END
FROM ranked
WHERE r.id = ranked.id;

WITH ranked AS (
  SELECT id, row_number() OVER (ORDER BY id) AS n FROM tournaments
)
UPDATE tournaments AS t
SET name = 'Capacity Tournament ' || ranked.n,
    share_token = CASE WHEN t.share_token IS NULL THEN NULL ELSE 'capacity-tournament-' || t.id END
FROM ranked
WHERE t.id = ranked.id;

UPDATE race_messages SET body = repeat('x', greatest(1, char_length(body)));

UPDATE step_samples
SET source_name = CASE WHEN source_name IS NULL THEN NULL ELSE 'capacity-source' END,
    source_id = NULL,
    source_device_id = NULL,
    device_model = NULL,
    metadata = CASE WHEN metadata IS NULL THEN NULL ELSE '{}'::jsonb END;

UPDATE step_samples_bak_5min_20260723
SET source_name = CASE WHEN source_name IS NULL THEN NULL ELSE 'capacity-source' END,
    source_id = NULL,
    source_device_id = NULL,
    device_model = NULL,
    metadata = CASE WHEN metadata IS NULL THEN NULL ELSE '{}'::jsonb END;

UPDATE step_samples_bak_5min_r2_20260724
SET source_name = CASE WHEN source_name IS NULL THEN NULL ELSE 'capacity-source' END,
    source_id = NULL,
    source_device_id = NULL,
    device_model = NULL,
    metadata = CASE WHEN metadata IS NULL THEN NULL ELSE '{}'::jsonb END;

UPDATE ad_reward_grants SET transaction_id = 'capacity-ad-' || id;
UPDATE onboarding_box_grant SET apple_sub_hash = 'capacity-onboarding-' || ctid::text;

-- These provider hashes are durable linkage keys used across account deletion.
-- Build one injective mapping for the entire payout family so velocity windows,
-- claim receipts, offers and rollout identities retain their original joins.
CREATE TEMP TABLE payout_hash_map ON COMMIT DROP AS
WITH provider_hashes AS (
  SELECT provider_sub_hash AS original_hash FROM race_payout_double_identities
  UNION
  SELECT provider_sub_hash FROM race_payout_double_offers
  UNION
  SELECT provider_sub_hash FROM race_payout_double_velocity_grants
  UNION
  SELECT provider_sub_hash FROM race_payout_double_claim_receipts
), ranked AS (
  SELECT original_hash, row_number() OVER (ORDER BY original_hash) AS n
  FROM provider_hashes
)
SELECT original_hash,
       'capacity-payout-hash-v1-' || lpad(n::text, 12, '0') AS sanitized_hash
FROM ranked;
ALTER TABLE payout_hash_map ADD PRIMARY KEY (original_hash);
ALTER TABLE payout_hash_map ADD UNIQUE (sanitized_hash);

UPDATE race_payout_double_identities AS i
SET provider_sub_hash = m.sanitized_hash
FROM payout_hash_map AS m
WHERE i.provider_sub_hash = m.original_hash;
UPDATE race_payout_double_offers AS o
SET provider_sub_hash = m.sanitized_hash
FROM payout_hash_map AS m
WHERE o.provider_sub_hash = m.original_hash;
UPDATE race_payout_double_velocity_grants AS v
SET provider_sub_hash = m.sanitized_hash
FROM payout_hash_map AS m
WHERE v.provider_sub_hash = m.original_hash;
UPDATE race_payout_double_claim_receipts AS c
SET provider_sub_hash = m.sanitized_hash
FROM payout_hash_map AS m
WHERE c.provider_sub_hash = m.original_hash;

-- Referral reward grants intentionally outlive their user/referral rows. Preserve
-- the per-human/per-role uniqueness key and any surviving referral linkage with a
-- second injective mapping shared by both durable tables.
CREATE TEMP TABLE referral_hash_map ON COMMIT DROP AS
WITH provider_hashes AS (
  SELECT referee_sub_hash AS original_hash FROM referrals
  UNION
  SELECT referee_sub_hash FROM referral_reward_grants
), ranked AS (
  SELECT original_hash, row_number() OVER (ORDER BY original_hash) AS n
  FROM provider_hashes
)
SELECT original_hash,
       'capacity-referral-hash-v1-' || lpad(n::text, 12, '0') AS sanitized_hash
FROM ranked;
ALTER TABLE referral_hash_map ADD PRIMARY KEY (original_hash);
ALTER TABLE referral_hash_map ADD UNIQUE (sanitized_hash);

UPDATE referrals
SET referee_sub_hash = m.sanitized_hash,
    code = CASE WHEN referrals.code IS NULL THEN NULL ELSE 'capacity-code-' || referrals.id END
FROM referral_hash_map AS m
WHERE referrals.referee_sub_hash = m.original_hash;
UPDATE referral_reward_grants AS g
SET referee_sub_hash = m.sanitized_hash
FROM referral_hash_map AS m
WHERE g.referee_sub_hash = m.original_hash;

COMMIT;
