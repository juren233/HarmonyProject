CREATE DATABASE powersync_storage;

CREATE TABLE IF NOT EXISTS pets (
  id text PRIMARY KEY,
  household_id text NOT NULL,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  owner_device_id text,
  role_priority integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS todos (
  id text PRIMARY KEY,
  household_id text NOT NULL,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  owner_device_id text,
  role_priority integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS reminders (
  id text PRIMARY KEY,
  household_id text NOT NULL,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  owner_device_id text,
  role_priority integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS records (
  id text PRIMARY KEY,
  household_id text NOT NULL,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  owner_device_id text,
  role_priority integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS devices (
  id text PRIMARY KEY,
  household_id text NOT NULL,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  role text,
  served_pet_id text,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint
);

CREATE TABLE IF NOT EXISTS pet_photo_assets (
  id text PRIMARY KEY,
  household_id text NOT NULL,
  pet_id text NOT NULL,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  owner_device_id text,
  role_priority integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS powersync_client_ops (
  client_op_id text PRIMARY KEY,
  household_id text NOT NULL,
  device_id text NOT NULL,
  table_name text NOT NULL,
  row_id text NOT NULL,
  operation text NOT NULL,
  applied_at_ms bigint NOT NULL
);

CREATE INDEX IF NOT EXISTS pets_household_updated_idx
  ON pets (household_id, updated_at_ms DESC);
CREATE INDEX IF NOT EXISTS todos_household_updated_idx
  ON todos (household_id, updated_at_ms DESC);
CREATE INDEX IF NOT EXISTS reminders_household_updated_idx
  ON reminders (household_id, updated_at_ms DESC);
CREATE INDEX IF NOT EXISTS records_household_updated_idx
  ON records (household_id, updated_at_ms DESC);
CREATE INDEX IF NOT EXISTS devices_household_updated_idx
  ON devices (household_id, updated_at_ms DESC);
CREATE INDEX IF NOT EXISTS pet_photo_assets_household_pet_idx
  ON pet_photo_assets (household_id, pet_id);

DROP PUBLICATION IF EXISTS powersync;
CREATE PUBLICATION powersync FOR TABLE
  pets,
  todos,
  reminders,
  records,
  devices,
  pet_photo_assets;
