\set ON_ERROR_STOP on

DO $$
DECLARE
  failures bigint;
BEGIN
  SELECT count(*) INTO failures
  FROM users
  WHERE apple_id IS NOT NULL
     OR google_sub IS NOT NULL
     OR profile_photo_url IS NOT NULL
     OR profile_photo_key IS NOT NULL
     OR email NOT LIKE 'capacity+%@example.invalid'
     OR name NOT LIKE 'Capacity User %'
     OR display_name NOT LIKE 'capacity_user_%';
  IF failures <> 0 THEN RAISE EXCEPTION 'user sanitization failures: %', failures; END IF;

  SELECT
    (SELECT count(*) FROM device_tokens) +
    (SELECT count(*) FROM notifications) +
    (SELECT count(*) FROM inbox_delivery_outbox) +
    (SELECT count(*) FROM inbox_alerts) +
    (SELECT count(*) FROM race_resolution_delivery_intents) +
    (SELECT count(*) FROM race_resolution_post_tasks) +
    (SELECT count(*) FROM race_resolution_jobs_v2) +
    (SELECT count(*) FROM race_resolution_jobs)
  INTO failures;
  IF failures <> 0 THEN RAISE EXCEPTION 'delivery/queued-work rows remain: %', failures; END IF;

  SELECT count(*) INTO failures
  FROM races
  WHERE name NOT LIKE 'Capacity Race %'
     OR (share_token IS NOT NULL AND share_token NOT LIKE 'capacity-race-%');
  IF failures <> 0 THEN RAISE EXCEPTION 'race sanitization failures: %', failures; END IF;

  SELECT count(*) INTO failures
  FROM tournaments
  WHERE name NOT LIKE 'Capacity Tournament %'
     OR (share_token IS NOT NULL AND share_token NOT LIKE 'capacity-tournament-%');
  IF failures <> 0 THEN RAISE EXCEPTION 'tournament sanitization failures: %', failures; END IF;

  SELECT count(*) INTO failures
  FROM race_messages
  WHERE body !~ '^x+$';
  IF failures <> 0 THEN RAISE EXCEPTION 'unsanitized race message bodies: %', failures; END IF;

  SELECT count(*) INTO failures
  FROM step_samples
  WHERE source_id IS NOT NULL
     OR source_device_id IS NOT NULL
     OR device_model IS NOT NULL
     OR (metadata IS NOT NULL AND metadata <> '{}'::jsonb)
     OR (source_name IS NOT NULL AND source_name <> 'capacity-source');
  IF failures <> 0 THEN RAISE EXCEPTION 'step sample identifiers remain: %', failures; END IF;

  SELECT count(*) INTO failures
  FROM (
    SELECT provider_sub_hash FROM race_payout_double_identities
    UNION ALL
    SELECT provider_sub_hash FROM race_payout_double_offers
    UNION ALL
    SELECT provider_sub_hash FROM race_payout_double_velocity_grants
    UNION ALL
    SELECT provider_sub_hash FROM race_payout_double_claim_receipts
  ) AS payout_hashes
  WHERE provider_sub_hash !~ '^capacity-payout-hash-v1-[0-9]{12}$';
  IF failures <> 0 THEN RAISE EXCEPTION 'unsanitized payout provider hashes: %', failures; END IF;

  SELECT
    (SELECT count(*)
       FROM race_payout_double_offers AS o
       LEFT JOIN race_payout_double_identities AS i
         ON i.provider_sub_hash = o.provider_sub_hash
      WHERE i.provider_sub_hash IS NULL) +
    (SELECT count(*)
       FROM race_payout_double_velocity_grants AS v
       LEFT JOIN race_payout_double_offers AS o ON o.id = v.offer_id
      WHERE o.id IS NULL OR o.provider_sub_hash <> v.provider_sub_hash) +
    (SELECT count(*)
       FROM race_payout_double_claim_receipts AS c
       LEFT JOIN race_payout_double_offers AS o ON o.id = c.offer_id
      WHERE o.id IS NULL OR o.provider_sub_hash <> c.provider_sub_hash)
  INTO failures;
  IF failures <> 0 THEN RAISE EXCEPTION 'payout provider hash linkage failures: %', failures; END IF;

  SELECT count(*) INTO failures
  FROM (
    SELECT referee_sub_hash FROM referrals
    UNION ALL
    SELECT referee_sub_hash FROM referral_reward_grants
  ) AS referral_hashes
  WHERE referee_sub_hash !~ '^capacity-referral-hash-v1-[0-9]{12}$';
  IF failures <> 0 THEN RAISE EXCEPTION 'unsanitized referral provider hashes: %', failures; END IF;

  SELECT count(*) INTO failures
  FROM referral_reward_grants AS g
  LEFT JOIN referrals AS r ON r.id = g.referral_id
  WHERE g.referral_id IS NOT NULL
    AND (r.id IS NULL OR r.referee_sub_hash <> g.referee_sub_hash);
  IF failures <> 0 THEN RAISE EXCEPTION 'referral provider hash linkage failures: %', failures; END IF;

  RAISE NOTICE 'sanitization validation passed';
END $$;
