import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import 'pos_database.dart';

/// One schema step. Ordered, hand-written, never generated.
///
/// The list is append-only: an applied migration is history and editing it
/// desynchronises every till that already ran it.
class PosMigration {
  const PosMigration(this.version, this.description, this.statements);

  final int version;
  final String description;
  final List<String> statements;
}

/// Advisory-lock key. Any constant, the same on every till.
///
/// Six terminals booting after an update will otherwise race the migration list
/// and two of them will try to create the same table. `pg_advisory_xact_lock`
/// serialises them and releases on commit, including on crash.
const _migrationLockKey = 727101;

/// The schema, in order.
///
/// Money is `bigint` minor units throughout — never `numeric`, never
/// `double precision`. The Dart type is `int` and the mapping is lossless, which
/// is the whole reason `Money` carries an exponent rather than assuming 100.
///
/// Timestamps are `timestamptz` without exception. A `timestamp` compared across
/// a Windows till and a macOS till is how an X report stops balancing.
const posMigrations = <PosMigration>[
  PosMigration(1, 'orders, lines, payments and the branch invoice sequence', [
    '''
    CREATE TABLE IF NOT EXISTS pos_invoice_sequences (
      restaurant_id  bigint      NOT NULL,
      branch_id      bigint      NOT NULL,
      period         text        NOT NULL,
      prefix         text        NOT NULL,
      next_value     bigint      NOT NULL DEFAULT 1,
      PRIMARY KEY (restaurant_id, branch_id, period)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pos_orders (
      id                     bigserial    PRIMARY KEY,
      client_transaction_id  uuid         NOT NULL,
      restaurant_id          bigint       NOT NULL,
      branch_id              bigint       NOT NULL,
      terminal_id            uuid         NOT NULL,
      invoice_number         text         NOT NULL,
      order_type             text         NOT NULL,
      table_id               bigint,
      table_label            text,
      guest_count            integer,
      currency               text         NOT NULL,
      exponent               smallint     NOT NULL,
      subtotal_minor         bigint       NOT NULL,
      service_minor          bigint       NOT NULL,
      vat_minor              bigint       NOT NULL,
      total_minor            bigint       NOT NULL,
      occurred_at            timestamptz  NOT NULL,
      received_at            timestamptz  NOT NULL DEFAULT now(),
      CONSTRAINT pos_orders_client_txn_unique
        UNIQUE (restaurant_id, client_transaction_id),
      CONSTRAINT pos_orders_invoice_unique
        UNIQUE (restaurant_id, branch_id, invoice_number),
      CONSTRAINT pos_orders_totals_sane
        CHECK (subtotal_minor >= 0 AND service_minor >= 0
               AND vat_minor >= 0 AND total_minor >= 0),
      CONSTRAINT pos_orders_guest_count_sane
        CHECK (guest_count IS NULL OR guest_count > 0)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pos_order_lines (
      id                bigserial   PRIMARY KEY,
      order_id          bigint      NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
      line_key          text        NOT NULL,
      menu_item_id      bigint,
      name_snapshot     text        NOT NULL,
      modifier_ids      bigint[]    NOT NULL DEFAULT '{}',
      modifier_summary  text,
      quantity          integer     NOT NULL,
      unit_price_minor  bigint      NOT NULL,
      line_total_minor  bigint      NOT NULL,
      stage             text        NOT NULL,
      note              text,
      CONSTRAINT pos_order_lines_quantity_positive CHECK (quantity > 0),
      CONSTRAINT pos_order_lines_prices_sane
        CHECK (unit_price_minor >= 0 AND line_total_minor >= 0)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS pos_order_lines_order_idx ON pos_order_lines (order_id)',
    // Payments are rows, not columns. Split tender is the normal case at a till:
    // "300 cash + 200 card" is two records, and columns on the order cannot
    // represent it. This is BE-A01, adopted.
    '''
    CREATE TABLE IF NOT EXISTS pos_order_payments (
      id             bigserial    PRIMARY KEY,
      order_id       bigint       NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
      tender_type_id bigint       NOT NULL,
      label          text         NOT NULL,
      amount_minor   bigint       NOT NULL,
      reference      varchar(80),
      occurred_at    timestamptz  NOT NULL DEFAULT now(),
      CONSTRAINT pos_order_payments_amount_positive CHECK (amount_minor > 0)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS pos_order_payments_order_idx ON pos_order_payments (order_id)',
  ]),
  // The restaurant's own data: who it is, where it trades, who works there and
  // what it sells. Until this existed the till read all of it from
  // `lib/data/fakes/`, which meant every installation opened showing a menu
  // belonging to a restaurant that does not exist.
  //
  // Money is `bigint` minor units here too, for the same reason as above: a
  // `numeric` price and an `int` price that disagree by a rounding step is a
  // receipt that does not foot.
  PosMigration(2, 'restaurants, branches, terminals, staff, menu and floor', [
    '''
    CREATE TABLE IF NOT EXISTS pos_restaurants (
      id         bigserial   PRIMARY KEY,
      slug       text        NOT NULL,
      name       text        NOT NULL,
      name_ar    text,
      tax_number text,
      is_active  boolean     NOT NULL DEFAULT true,
      created_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_restaurants_slug_unique UNIQUE (slug)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pos_branches (
      id                    bigserial   PRIMARY KEY,
      restaurant_id         bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      code                  text        NOT NULL,
      name                  text        NOT NULL,
      supported_order_types text[]      NOT NULL DEFAULT '{}',
      is_active             boolean     NOT NULL DEFAULT true,
      created_at            timestamptz NOT NULL DEFAULT now(),
      -- The invoice prefix. Two branches sharing one would collide in
      -- pos_invoice_sequences, which is keyed on (restaurant, branch, period).
      CONSTRAINT pos_branches_code_unique UNIQUE (restaurant_id, code)
    )
    ''',
    // The terminal row exists before the machine does — that inversion is what
    // makes an offline till trackable at all (POS-BE-023). A till that never
    // claims is visibly a till that never activated.
    '''
    CREATE TABLE IF NOT EXISTS pos_terminals (
      id            uuid        PRIMARY KEY,
      restaurant_id bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id     bigint      NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      name          text        NOT NULL,
      pairing_code  text,
      sync_policy   text        NOT NULL DEFAULT 'automatic',
      claimed_at    timestamptz,
      created_at    timestamptz NOT NULL DEFAULT now(),
      -- Nulls do not collide in a UNIQUE index, so a spent code (set to null on
      -- claim) frees the slot without any special casing.
      CONSTRAINT pos_terminals_pairing_code_unique UNIQUE (restaurant_id, pairing_code),
      CONSTRAINT pos_terminals_sync_policy_known CHECK (sync_policy IN ('automatic', 'manual'))
    )
    ''',
    // PIN salt and hash, never the PIN. PBKDF2 at the iteration count in
    // `lib/core/security/pin_hash.dart` — a four-digit secret needs the work
    // factor to be worth anything at all.
    '''
    CREATE TABLE IF NOT EXISTS pos_staff (
      id            bigserial   PRIMARY KEY,
      restaurant_id bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id     bigint      REFERENCES pos_branches(id) ON DELETE CASCADE,
      name          text        NOT NULL,
      username      text        NOT NULL,
      pin_salt      text        NOT NULL,
      pin_hash      text        NOT NULL,
      capabilities  text[]      NOT NULL DEFAULT '{}',
      is_active     boolean     NOT NULL DEFAULT true,
      created_at    timestamptz NOT NULL DEFAULT now(),
      -- Usernames are unique per restaurant, not globally: that is why the
      -- tenant has to be known before anyone can sign in.
      CONSTRAINT pos_staff_username_unique UNIQUE (restaurant_id, username)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pos_categories (
      id            bigserial PRIMARY KEY,
      restaurant_id bigint    NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      name_en       text      NOT NULL,
      name_ar       text,
      slug          text,
      sort_order    integer   NOT NULL DEFAULT 0,
      is_active     boolean   NOT NULL DEFAULT true
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pos_modifier_groups (
      id            bigserial PRIMARY KEY,
      restaurant_id bigint    NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      name_en       text      NOT NULL,
      name_ar       text,
      is_required   boolean   NOT NULL DEFAULT false,
      max_select    integer   NOT NULL DEFAULT 1,
      is_variant    boolean   NOT NULL DEFAULT false,
      sort_order    integer   NOT NULL DEFAULT 0,
      CONSTRAINT pos_modifier_groups_max_select_sane CHECK (max_select >= 1)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pos_modifiers (
      id                bigserial PRIMARY KEY,
      group_id          bigint    NOT NULL REFERENCES pos_modifier_groups(id) ON DELETE CASCADE,
      name_en           text      NOT NULL,
      name_ar           text,
      -- May be zero ("no onions") or negative, so no non-negative check here.
      price_delta_minor bigint    NOT NULL DEFAULT 0,
      is_available      boolean   NOT NULL DEFAULT true,
      sort_order        integer   NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS pos_modifiers_group_idx ON pos_modifiers (group_id)',
    '''
    CREATE TABLE IF NOT EXISTS pos_products (
      id                     bigserial PRIMARY KEY,
      restaurant_id          bigint    NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      category_id            bigint    NOT NULL REFERENCES pos_categories(id) ON DELETE RESTRICT,
      name_en                text      NOT NULL,
      name_ar                text,
      price_minor            bigint    NOT NULL,
      discounted_price_minor bigint,
      sku                    text,
      barcode                text,
      is_available           boolean   NOT NULL DEFAULT true,
      sort_order             integer   NOT NULL DEFAULT 0,
      CONSTRAINT pos_products_price_sane
        CHECK (price_minor >= 0
               AND (discounted_price_minor IS NULL OR discounted_price_minor >= 0)),
      CONSTRAINT pos_products_sku_unique UNIQUE (restaurant_id, sku)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS pos_products_category_idx ON pos_products (category_id)',
    // A scanner needs an exact match to be fast and unambiguous.
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_products_barcode_unique
      ON pos_products (restaurant_id, barcode) WHERE barcode IS NOT NULL
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pos_product_modifier_groups (
      product_id bigint  NOT NULL REFERENCES pos_products(id) ON DELETE CASCADE,
      group_id   bigint  NOT NULL REFERENCES pos_modifier_groups(id) ON DELETE CASCADE,
      sort_order integer NOT NULL DEFAULT 0,
      PRIMARY KEY (product_id, group_id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pos_dining_tables (
      id            bigserial PRIMARY KEY,
      restaurant_id bigint    NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id     bigint    NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      label         text      NOT NULL,
      seats         integer   NOT NULL,
      area_name     text,
      sort_order    integer   NOT NULL DEFAULT 0,
      is_active     boolean   NOT NULL DEFAULT true,
      CONSTRAINT pos_dining_tables_label_unique UNIQUE (branch_id, label),
      CONSTRAINT pos_dining_tables_seats_positive CHECK (seats > 0)
    )
    ''',
  ]),
  // Shifts, and the drawer count that closes one.
  //
  // Until this existed, *Close shift* navigated to the start screen and did
  // nothing else: no shift was ever opened, no cash was counted, and the button
  // discarded whatever was on the ticket without asking. A till that cannot say
  // how much cash should be in the drawer is a till nobody can hold responsible
  // for what is in it.
  PosMigration(3, 'shifts, the drawer count, and the shift a sale belongs to', [
    '''
    CREATE TABLE IF NOT EXISTS pos_shifts (
      id                  bigserial   PRIMARY KEY,
      restaurant_id       bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id           bigint      NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      terminal_id         uuid        NOT NULL REFERENCES pos_terminals(id) ON DELETE CASCADE,
      -- Who is answerable for the drawer. RESTRICT, not CASCADE: deleting a
      -- member of staff must not delete the record of the money they counted.
      opened_by           bigint      NOT NULL REFERENCES pos_staff(id) ON DELETE RESTRICT,
      closed_by           bigint      REFERENCES pos_staff(id) ON DELETE RESTRICT,
      opened_at           timestamptz NOT NULL DEFAULT now(),
      opening_float_minor bigint      NOT NULL DEFAULT 0,
      closed_at           timestamptz,
      counted_cash_minor  bigint,
      expected_cash_minor bigint,
      -- Stored rather than derived. It is the number a manager argues about, and
      -- recomputing it later from rows that may have changed would quietly
      -- rewrite history.
      variance_minor      bigint,
      closing_note        text,
      CONSTRAINT pos_shifts_float_sane CHECK (opening_float_minor >= 0),
      CONSTRAINT pos_shifts_counted_sane
        CHECK (counted_cash_minor IS NULL OR counted_cash_minor >= 0),
      -- A shift is open or it is closed. Half-closed — a closing time with no
      -- count, or a count with no closing time — is not a state anyone can act
      -- on, so the database refuses to hold one.
      CONSTRAINT pos_shifts_closed_is_complete CHECK (
        (closed_at IS NULL AND counted_cash_minor IS NULL
                           AND expected_cash_minor IS NULL
                           AND variance_minor IS NULL
                           AND closed_by IS NULL)
        OR
        (closed_at IS NOT NULL AND counted_cash_minor IS NOT NULL
                               AND expected_cash_minor IS NOT NULL
                               AND variance_minor IS NOT NULL
                               AND closed_by IS NOT NULL)
      )
    )
    ''',
    // The rule the whole feature rests on. Two open shifts on one till means two
    // people each believe they are answerable for the same drawer, and the
    // second cash-up silently contradicts the first.
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_shifts_one_open_per_terminal
      ON pos_shifts (terminal_id) WHERE closed_at IS NULL
    ''',
    'CREATE INDEX IF NOT EXISTS pos_shifts_branch_opened_idx ON pos_shifts (branch_id, opened_at)',
    // Nullable, because every order written before this migration belongs to no
    // shift and inventing one for them would be a lie in the ledger.
    'ALTER TABLE pos_orders ADD COLUMN IF NOT EXISTS shift_id bigint REFERENCES pos_shifts(id)',
    'CREATE INDEX IF NOT EXISTS pos_orders_shift_idx ON pos_orders (shift_id)',
  ]),

  // The outbound queue. Only cloud terminals write to it — an offline terminal
  // never sends sales anywhere, and a queue that nothing drains is a table that
  // grows until someone notices.
  //
  // **There is no payload column, on purpose.** What a synced order looks like
  // on the wire is POS-BE-007's decision and it is still `PROPOSED`; snapshotting
  // a format we invented would mean rewriting every queued row when the real one
  // lands. Orders here are write-once, so referencing `pos_orders` loses nothing
  // that a snapshot would have preserved, and the drain can serialise from the
  // order when there is finally a contract to serialise it into.
  PosMigration(4, 'the outbound sync queue', [
    '''
    CREATE TABLE IF NOT EXISTS pos_outbox (
      id                     bigserial   PRIMARY KEY,
      order_id               bigint      NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
      -- Carried alongside the order id because it is the idempotency key the
      -- drain will send, and it must survive being read without a join.
      client_transaction_id  uuid        NOT NULL,
      restaurant_id          bigint      NOT NULL,
      branch_id              bigint      NOT NULL,
      enqueued_at            timestamptz NOT NULL DEFAULT now(),
      attempts               integer     NOT NULL DEFAULT 0,
      last_attempt_at        timestamptz,
      last_error             text,
      -- NULL means still owed to the platform. Set, never deleted: a till that
      -- forgets it already sent a sale is a till that sends it twice.
      delivered_at           timestamptz,
      CONSTRAINT pos_outbox_attempts_sane CHECK (attempts >= 0)
    )
    ''',
    // One entry per sale. A retried submit replays into the same order row, and
    // it must not leave two claims on the same money behind it.
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_outbox_one_per_order
      ON pos_outbox (restaurant_id, client_transaction_id)
    ''',
    // The only query the till runs on this table often: how much is still owed.
    // Partial, so its size tracks the backlog rather than the sales history.
    '''
    CREATE INDEX IF NOT EXISTS pos_outbox_pending_idx
      ON pos_outbox (restaurant_id, branch_id, enqueued_at)
      WHERE delivered_at IS NULL
    ''',
  ]),
  // Roles, the permission model they carry, and the record of what anyone did
  // with them. Local administration has to work with the platform unreachable,
  // so all three live on the branch database beside the catalogue they protect.
  //
  // Capabilities were already a `text[]` on `pos_staff` — granted per person,
  // by hand, by whoever ran `--seed`. That does not survive a restaurant with
  // eleven cashiers: nobody can answer "what may a cashier do here?" without
  // reading eleven arrays, and the answer is usually that they differ. A role
  // is the thing a manager actually thinks in.
  //
  // The direct grants stay. They are the exception a small restaurant needs —
  // one cashier who is also trusted to reprint — and removing them would force
  // that person into a role that gives them far more.
  PosMigration(5, 'roles, audited administration and catalogue revisions', [
    '''
    CREATE TABLE IF NOT EXISTS pos_roles (
      id            bigserial   PRIMARY KEY,
      restaurant_id bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      -- Machine-readable and stable. A restaurant renaming "Supervisor" to
      -- "Shift Lead" must not change what the seed, the tests and the override
      -- flow refer to.
      code          text        NOT NULL,
      name_en       text        NOT NULL,
      name_ar       text,
      capabilities  text[]      NOT NULL DEFAULT '{}',
      -- Seeded by the installer. Editable, never deletable: deleting the last
      -- role holding `staff.manage` locks everyone out of the only screen that
      -- could put it back.
      is_system     boolean     NOT NULL DEFAULT false,
      created_at    timestamptz NOT NULL DEFAULT now(),
      updated_at    timestamptz NOT NULL DEFAULT now(),
      -- Per restaurant, not global. Two restaurants sharing a branch server
      -- must not share a definition of "manager".
      CONSTRAINT pos_roles_code_unique UNIQUE (restaurant_id, code)
    )
    ''',
    // ON DELETE RESTRICT, not SET NULL. Deleting a role somebody holds would
    // silently strip them back to their direct grants — a demotion nobody asked
    // for and nothing recorded. The repository names who is still on the role
    // instead, and reassignment is a deliberate act.
    '''
    ALTER TABLE pos_staff
      ADD COLUMN IF NOT EXISTS role_id bigint REFERENCES pos_roles(id) ON DELETE RESTRICT
    ''',

    // The capability names the first build shipped, rewritten to the ones the
    // specification settled on.
    //
    // **This is not cosmetic.** `--seed` wrote `pos.shift_open`, `pos.reprint`
    // and friends to every staff row on every branch server that has run this
    // build. Under the new names those strings match nothing, so without this
    // statement the upgrade would silently strip each of those people back to
    // `pos.operate` — a permission change nobody made and nothing recorded.
    // Mirrors `PosCapability.canonical`, which is what a till on an older
    // binary uses to read a row this has already rewritten.
    '''
    UPDATE pos_staff SET capabilities = (
      SELECT array_agg(DISTINCT CASE capability
        WHEN 'pos.discount'       THEN 'discount.apply'
        WHEN 'pos.shift_open'     THEN 'shift.open'
        WHEN 'pos.shift_close'    THEN 'shift.close'
        WHEN 'pos.cash_movement'  THEN 'cash.movement'
        WHEN 'pos.reprint'        THEN 'receipt.reprint'
        WHEN 'pos.void'           THEN 'order.void'
        WHEN 'pos.refund'         THEN 'order.refund'
        WHEN 'pos.price_override' THEN 'price.override'
        WHEN 'pos.reports'        THEN 'reports.view'
        ELSE capability
      END)
      FROM unnest(capabilities) AS capability
    )
    WHERE capabilities && ARRAY[
      'pos.discount', 'pos.shift_open', 'pos.shift_close', 'pos.cash_movement',
      'pos.reprint', 'pos.void', 'pos.refund', 'pos.price_override', 'pos.reports'
    ]
    ''',

    // Who did what, to which record, with the value before and after.
    //
    // **No foreign keys, deliberately.** An audit row has to outlive the thing
    // it describes: the whole point of recording that a product was deleted is
    // that the product is gone, and a cascade would take the evidence with the
    // subject. RESTRICT is no better — it makes the audit trail a reason you
    // cannot tidy up a branch, which is how people learn to want it gone.
    // Names are denormalised for the same reason: a member of staff who is
    // later renamed or disabled must still appear here under the name they had
    // at the time.
    '''
    CREATE TABLE IF NOT EXISTS pos_audit_events (
      id               bigserial   PRIMARY KEY,
      restaurant_id    bigint      NOT NULL,
      branch_id        bigint,
      terminal_id      uuid,
      shift_id         bigint,
      actor_staff_id   bigint,
      actor_name       text        NOT NULL,
      -- Set only when a supervisor lent a permission for this one action. Both
      -- people are on the row: an approved discount with no approver recorded
      -- is indistinguishable from one nobody approved.
      approved_by_id   bigint,
      approved_by_name text,
      action           text        NOT NULL,
      entity_type      text        NOT NULL,
      entity_id        text,
      -- jsonb, not text: "every price change on this product" is a query the
      -- audit report actually runs, and a string would make it a scan with a
      -- LIKE in it.
      before_value     jsonb,
      after_value      jsonb,
      reason           text,
      occurred_at      timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_audit_events_action_present CHECK (length(trim(action)) > 0),
      CONSTRAINT pos_audit_events_entity_present CHECK (length(trim(entity_type)) > 0),
      CONSTRAINT pos_audit_events_actor_present CHECK (length(trim(actor_name)) > 0)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_audit_events_tenant_time_idx
      ON pos_audit_events (restaurant_id, occurred_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_audit_events_entity_idx
      ON pos_audit_events (restaurant_id, entity_type, entity_id, occurred_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_audit_events_actor_idx
      ON pos_audit_events (restaurant_id, actor_staff_id, occurred_at DESC)
    ''',

    // Append-only, held by the database rather than by convention.
    //
    // The till connects as `pos_till`, which is granted INSERT and SELECT here
    // and nothing else, so in normal operation this never fires. It exists for
    // the case the grant does not cover: somebody with a psql prompt and the
    // admin password — which, on a branch server sitting in a restaurant, is a
    // fair description of the person most motivated to edit the row naming
    // them.
    //
    // TRUNCATE is covered too. It is not a DELETE, it fires no row triggers,
    // and it is precisely how a table gets emptied by someone who has just
    // discovered that DELETE is blocked.
    r'''
    CREATE OR REPLACE FUNCTION pos_audit_events_append_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'pos_audit_events is append-only; % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql
    ''',
    'DROP TRIGGER IF EXISTS pos_audit_events_no_rewrite ON pos_audit_events',
    '''
    CREATE TRIGGER pos_audit_events_no_rewrite
      BEFORE UPDATE OR DELETE ON pos_audit_events
      FOR EACH ROW EXECUTE FUNCTION pos_audit_events_append_only()
    ''',
    'DROP TRIGGER IF EXISTS pos_audit_events_no_truncate ON pos_audit_events',
    '''
    CREATE TRIGGER pos_audit_events_no_truncate
      BEFORE TRUNCATE ON pos_audit_events
      FOR EACH STATEMENT EXECUTE FUNCTION pos_audit_events_append_only()
    ''',

    // Catalogue rows carry a revision so that two managers editing the same
    // product over the LAN cannot silently overwrite each other — the second
    // save is refused with the current row rather than applied on top. The
    // columns land here, with the permission that governs who may write them,
    // so that catalogue management is a screen away rather than a migration
    // away on every site.
    'ALTER TABLE pos_categories ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1',
    'ALTER TABLE pos_categories ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()',
    'ALTER TABLE pos_products ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1',
    'ALTER TABLE pos_products ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()',
    'ALTER TABLE pos_modifier_groups ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1',
    'ALTER TABLE pos_modifier_groups ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()',
    'ALTER TABLE pos_modifiers ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1',
    'ALTER TABLE pos_modifiers ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_categories_slug_unique
      ON pos_categories (restaurant_id, lower(slug)) WHERE slug IS NOT NULL
    ''',

    // Backfill the four system roles for restaurants already on this server.
    // New restaurants get theirs from `SystemRoles` in `bin/pos_migrate.dart` —
    // that constant is the living definition, and the literals below are frozen
    // history, which is why they are spelled out rather than interpolated.
    '''
    INSERT INTO pos_roles (restaurant_id, code, name_en, name_ar, capabilities, is_system)
    SELECT r.id, seed.code, seed.name_en, seed.name_ar, seed.capabilities, true
    FROM pos_restaurants r
    CROSS JOIN (VALUES
      ('owner', 'Owner', 'المالك', ARRAY[
        'pos.operate','catalog.view','catalog.manage','staff.manage',
        'terminal.manage','settings.manage','discount.apply','price.override',
        'order.void','order.refund','receipt.reprint','shift.open','shift.close',
        'cash.movement','reports.view','backup.manage']::text[]),
      ('manager', 'Manager', 'مدير', ARRAY[
        'pos.operate','catalog.view','catalog.manage','staff.manage',
        'settings.manage','discount.apply','price.override','order.void',
        'order.refund','receipt.reprint','shift.open','shift.close',
        'cash.movement','reports.view']::text[]),
      ('supervisor', 'Supervisor', 'مشرف', ARRAY[
        'pos.operate','catalog.view','discount.apply','price.override',
        'order.void','order.refund','receipt.reprint','shift.open','shift.close',
        'cash.movement','reports.view']::text[]),
      ('cashier', 'Cashier', 'كاشير', ARRAY[
        'pos.operate','catalog.view','receipt.reprint','shift.open',
        'shift.close']::text[])
    ) AS seed(code, name_en, name_ar, capabilities)
    ON CONFLICT (restaurant_id, code) DO NOTHING
    ''',

    // The oldest staff row is the account `--seed` created: the installer chose
    // its PIN and it is the only credential the restaurant has. It becomes the
    // owner, because otherwise this migration leaves a branch server on which
    // nobody holds `staff.manage` and therefore nobody can grant it — the
    // Management screen would be unreachable on every existing install.
    //
    // Everyone else starts as a cashier. They keep their direct grants on top,
    // so this only ever adds; and a cashier role is the floor, not a guess at
    // what somebody was trusted with.
    '''
    WITH ranked AS (
      SELECT id, restaurant_id,
             row_number() OVER (PARTITION BY restaurant_id ORDER BY created_at, id) AS position
      FROM pos_staff WHERE role_id IS NULL
    )
    UPDATE pos_staff s
    SET role_id = r.id
    FROM ranked x
    JOIN pos_roles r ON r.restaurant_id = x.restaurant_id
                    AND r.code = CASE WHEN x.position = 1 THEN 'owner' ELSE 'cashier' END
    WHERE s.id = x.id
    ''',
  ]),
  // What the platform said about each drained sale, and where this till stands
  // against the platform's configuration counter.
  //
  // The outbox gains the drain's bookkeeping: the server's id and invoice
  // number come back on delivery (POS-BE-006) and are kept beside the local
  // row, because the locally-printed reference was always provisional and the
  // authoritative number must be findable afterwards. `quarantined_at` marks a
  // record the platform *rejected for cause* (POS-BE-019) — held out of the
  // retry loop but never deleted, because a rejected sale is still money that
  // changed hands and a person has to decide what happens to it.
  PosMigration(6, 'cloud drain bookkeeping and the platform config version', [
    'ALTER TABLE pos_outbox ADD COLUMN IF NOT EXISTS server_order_id bigint',
    'ALTER TABLE pos_outbox ADD COLUMN IF NOT EXISTS server_invoice_number text',
    'ALTER TABLE pos_outbox ADD COLUMN IF NOT EXISTS totals_mismatch boolean NOT NULL DEFAULT false',
    'ALTER TABLE pos_outbox ADD COLUMN IF NOT EXISTS quarantined_at timestamptz',
    'ALTER TABLE pos_outbox ADD COLUMN IF NOT EXISTS quarantine_code text',
    // One row per restaurant: the last accepted `config_version` (the client's
    // sole precedence signal, POS-BE-025 — a lower incoming value is a rollback
    // and is refused) and when the catalog was last seeded from the platform.
    '''
    CREATE TABLE IF NOT EXISTS pos_cloud_state (
      restaurant_id        bigint      PRIMARY KEY,
      config_version       bigint      NOT NULL DEFAULT 0,
      bootstrap_synced_at  timestamptz,
      updated_at           timestamptz NOT NULL DEFAULT now()
    )
    ''',
  ]),
  // The open floor, durably. A parked table ticket is real trade in
  // progress — seats held, food possibly fired — and losing it to an app
  // restart mid-service was the sharpest data loss left in the till.
  //
  // One row per (restaurant, table); the whole ticket rides a jsonb payload
  // written by the data layer's codec. **This is the one legitimately
  // deletable POS row**: settlement removes it because the money has moved
  // into pos_orders, where the durable record lives. Everything else in this
  // schema keeps its no-DELETE discipline.
  PosMigration(7, 'parked table tickets — the open floor survives a restart', [
    '''
    CREATE TABLE IF NOT EXISTS pos_parked_tickets (
      restaurant_id          bigint      NOT NULL,
      table_id               bigint      NOT NULL,
      client_transaction_id  uuid        NOT NULL,
      payload                jsonb       NOT NULL,
      parked_at              timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (restaurant_id, table_id)
    )
    ''',
  ]),
  // The platform's money rules, cached where the ticket can reach them.
  //
  // Until this existed the till priced tax from a device-config default —
  // 12% service, 14% VAT — while the platform priced from the tenant's own
  // rules. A tenant with no rules configured therefore had its customers
  // charged 27.68% more than the ledger recorded, caught only by the
  // `totals_mismatch` flag after the money had moved. POS-BE-013 makes the
  // SERVER the author of tax; this is where its answer lives.
  PosMigration(8, 'money configuration, authored by the platform', [
    '''
    CREATE TABLE IF NOT EXISTS pos_money_config (
      restaurant_id bigint      PRIMARY KEY,
      payload       jsonb       NOT NULL,
      synced_at     timestamptz NOT NULL DEFAULT now()
    )
    ''',
  ]),
  // An order that can be unmade, and the record of who unmade it.
  //
  // Until now `pos_orders` was written **only at settlement** and never touched
  // again. That is a fine shape for a till that can only sell: the row appears
  // when the money moves and is true forever. It is not a shape that can hold a
  // void, because a void is a thing that happens to an order that already
  // exists, and the till had nowhere to write it — `_void()` on the sale screen
  // cleared the widget's state and told nobody.
  //
  // Three things arrive together because none of them is useful alone: a
  // lifecycle the order can move through, the reasons a person picks from, and
  // a per-line event log that can tell *removed before it was cooked* from
  // *thrown away after it was*. The SRS is emphatic that those two are not the
  // same act, and a schema that records both as "line gone" cannot ever be
  // asked which happened.
  //
  // **The money columns stay immutable.** Nothing here lets a total be
  // rewritten: the new columns are status and provenance, and the till's grant
  // is column-scoped to exactly them — see `LocalBootstrap.tillGrants`.
  PosMigration(9, 'order lifecycle, void provenance and reason codes', [
    // Every row that exists today is a settled sale, so PAID is the only
    // honest default. Inventing DRAFT or CLOSED for history would be a
    // statement about orders nobody made.
    '''
    ALTER TABLE pos_orders ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'PAID'
    ''',
    // Added separately from the column so a re-run is safe and so the
    // constraint can be named — an unnamed CHECK is one nobody can drop later
    // without looking it up.
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_orders ADD CONSTRAINT pos_orders_status_known CHECK (
        status IN ('DRAFT','OPEN','SENT_TO_KITCHEN','READY','PAID','CLOSED',
                   'VOIDED','CANCELLED','REFUNDED','PARTIALLY_REFUNDED'));
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',
    '''
    ALTER TABLE pos_orders
      ADD COLUMN IF NOT EXISTS status_changed_at timestamptz NOT NULL DEFAULT now()
    ''',
    // RESTRICT, not CASCADE: deleting a member of staff must never delete the
    // record of what they voided. Same rule `pos_shifts.closed_by` follows.
    '''
    ALTER TABLE pos_orders
      ADD COLUMN IF NOT EXISTS voided_by bigint REFERENCES pos_staff(id) ON DELETE RESTRICT
    ''',
    'ALTER TABLE pos_orders ADD COLUMN IF NOT EXISTS voided_at timestamptz',
    'ALTER TABLE pos_orders ADD COLUMN IF NOT EXISTS void_reason_id bigint',
    'ALTER TABLE pos_orders ADD COLUMN IF NOT EXISTS void_note text',
    // No foreign key yet — `pos_business_days` arrives in migration 12. The
    // column lands now so that Wave A's writes can stamp it from the day it
    // exists rather than needing a backfill of orders nobody can re-date.
    'ALTER TABLE pos_orders ADD COLUMN IF NOT EXISTS business_day_id bigint',
    // A void is either complete or it did not happen. A voided_at with no one
    // against it is a row that says the order was cancelled and refuses to say
    // by whom — which is precisely the row somebody would want to leave.
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_orders ADD CONSTRAINT pos_orders_void_is_attributed CHECK (
        (voided_at IS NULL AND voided_by IS NULL)
        OR (voided_at IS NOT NULL AND voided_by IS NOT NULL));
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_orders_status_idx
      ON pos_orders (restaurant_id, status, occurred_at DESC)
    ''',

    'ALTER TABLE pos_order_lines ADD COLUMN IF NOT EXISTS voided_at timestamptz',
    '''
    ALTER TABLE pos_order_lines
      ADD COLUMN IF NOT EXISTS voided_by bigint REFERENCES pos_staff(id) ON DELETE RESTRICT
    ''',
    'ALTER TABLE pos_order_lines ADD COLUMN IF NOT EXISTS void_reason_id bigint',
    // How much of this line has already been given back. A counter rather than
    // a sum over `pos_refund_lines` because it is the number the *next* refund
    // has to check, inside the same transaction, under the same row lock —
    // recomputing it from another table is how a line gets refunded twice.
    // Migration 11 adds the refund tables that maintain it.
    '''
    ALTER TABLE pos_order_lines
      ADD COLUMN IF NOT EXISTS refunded_quantity integer NOT NULL DEFAULT 0
    ''',
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_order_lines ADD CONSTRAINT pos_order_lines_refunded_within_sold
        CHECK (refunded_quantity >= 0 AND refunded_quantity <= quantity);
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',

    // Why somebody did it. One list, narrowed by scope, shared by every act
    // that has to answer for itself — see `SystemReasons`, which is the living
    // definition this migration freezes a copy of below.
    //
    // `requires_note` is on the row rather than the list on purpose: within one
    // picker, "Wrong item made" explains itself and "Other" does not, and a
    // list-level flag would force a note for all of them or for none.
    '''
    CREATE TABLE IF NOT EXISTS pos_reason_codes (
      id            bigserial   PRIMARY KEY,
      restaurant_id bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      scope         text        NOT NULL,
      code          text        NOT NULL,
      name_en       text        NOT NULL,
      name_ar       text,
      requires_note boolean     NOT NULL DEFAULT false,
      sort_order    integer     NOT NULL DEFAULT 0,
      is_active     boolean     NOT NULL DEFAULT true,
      created_at    timestamptz NOT NULL DEFAULT now(),
      updated_at    timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_reason_codes_scope_known CHECK (scope IN (
        'void','refund','discount','price_override',
        'pay_in','pay_out','waste','adjustment')),
      -- Per restaurant and per scope. Two restaurants on one branch server keep
      -- their own vocabularies, and the same code may legitimately mean
      -- something in a void list and something else in a waste list.
      CONSTRAINT pos_reason_codes_code_unique UNIQUE (restaurant_id, scope, code)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_reason_codes_pick_idx
      ON pos_reason_codes (restaurant_id, scope, sort_order) WHERE is_active
    ''',

    // What happened to a line, in order.
    //
    // The distinction this table exists for: removing a line before it is fired
    // is housekeeping, and voiding one after the kitchen has cooked it is
    // waste with a cost attached. Both leave the line off the bill. Only this
    // records which of the two occurred, who did it and who approved it.
    //
    // No foreign keys to staff, and names are not carried here because the
    // audit ledger already denormalises them — this table is the operational
    // record and `pos_audit_events` is the one that has to outlive its subject.
    '''
    CREATE TABLE IF NOT EXISTS pos_order_line_events (
      id                      bigserial   PRIMARY KEY,
      order_id                bigint      NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
      order_line_id           bigint      REFERENCES pos_order_lines(id) ON DELETE CASCADE,
      -- Survives the line being removed before it was ever persisted, which is
      -- the whole point of recording a cancel.
      line_key                text        NOT NULL,
      event                   text        NOT NULL,
      quantity_before         integer,
      quantity_after          integer,
      unit_price_before_minor bigint,
      unit_price_after_minor  bigint,
      reason_id               bigint,
      note                    text,
      staff_id                bigint      NOT NULL,
      approved_by_id          bigint,
      occurred_at             timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_order_line_events_event_known CHECK (event IN (
        'added','quantity_changed','removed_before_send','voided_after_send',
        'price_overridden','discounted','refunded'))
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_order_line_events_order_idx
      ON pos_order_line_events (order_id, occurred_at)
    ''',

    // The ten reasons, for restaurants that already exist on this server.
    //
    // Frozen literals rather than an interpolation of `SystemReasons`, for the
    // same reason migration 5's role seed is: an applied migration is history,
    // and history that changes when a Dart constant is edited is not history.
    // New restaurants are seeded from the constant by `LocalBootstrap`.
    '''
    INSERT INTO pos_reason_codes
      (restaurant_id, scope, code, name_en, name_ar, requires_note, sort_order)
    SELECT r.id, s.scope, seed.code, seed.name_en, seed.name_ar,
           seed.requires_note, seed.sort_order
    FROM pos_restaurants r
    CROSS JOIN (VALUES ('void'), ('refund'), ('discount'), ('price_override'))
      AS s(scope)
    CROSS JOIN (VALUES
      ('customer_complaint', 'Customer complaint',       'شكوى عميل',              false,  1),
      ('wrong_item',         'Wrong item made',          'صنف خطأ في التحضير',      false,  2),
      ('unavailable',        'Item unavailable (86''d)',  'الصنف غير متوفر',        false,  3),
      ('staff_meal',         'Staff meal',               'وجبة موظفين',            false,  4),
      ('manager_comp',       'Manager comp',             'ضيافة إدارة',            false,  5),
      ('price_differs',      'Price differs from menu',  'سعر مختلف عن القائمة',    false,  6),
      ('kitchen_delay',      'Kitchen took too long',    'تأخر التحضير',           false,  7),
      ('training',           'Training',                 'تدريب',                  false,  8),
      ('regular_gesture',    'Regular-customer gesture', 'مجاملة عميل دائم',        false,  9),
      ('other',              'Other — note required',    'أخرى — يلزم كتابة ملاحظة', true,  10)
    ) AS seed(code, name_en, name_ar, requires_note, sort_order)
    ON CONFLICT (restaurant_id, scope, code) DO NOTHING
    ''',
  ]),
  // Money off, and the record of who took it off.
  //
  // The till has had exactly one kind of discount until now: a
  // `discounted_price_minor` on the product, which is a *price*, not a
  // discount. It cannot be applied to an order, cannot be applied by a person,
  // carries no reason, no approver and no audit, and cannot be reported on —
  // "what did we give away last month, and who authorised it" has been an
  // unanswerable question.
  //
  // Two tables, and the split between them is the whole design. `pos_discounts`
  // is the restaurant's **configuration** — editable, versioned, and free to
  // change tomorrow. `pos_order_discounts` is a **snapshot** taken at the
  // moment of sale, holding the name, the kind and the value as they were. A
  // restaurant that renames "Staff meal" or takes 10% to 15% must not thereby
  // rewrite what a customer was charged in March, which is the same rule
  // `pos_order_lines.name_snapshot` already follows for the food.
  //
  // **Nothing is seeded.** A discount is a commercial decision, and a till that
  // arrived with somebody else's promotion configured would be inventing one.
  PosMigration(10, 'discounts, and the record of who applied them', [
    '''
    CREATE TABLE IF NOT EXISTS pos_discounts (
      id                 bigserial   PRIMARY KEY,
      restaurant_id      bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      code               text        NOT NULL,
      name_en            text        NOT NULL,
      name_ar            text,
      kind               text        NOT NULL,
      -- Basis points for a percentage, minor units for a fixed amount. Never a
      -- float and never one column doing both jobs: 1250 is 12.5% and 1250 is
      -- also 12.50 EGP, and a single column would make those indistinguishable
      -- the first time somebody read the table without the `kind` beside it.
      value_bp           integer,
      value_minor        bigint,
      scope              text        NOT NULL,
      min_order_minor    bigint,
      -- The cap on a percentage discount — "20% off, up to 50 EGP".
      max_discount_minor bigint,
      starts_at          timestamptz,
      ends_at            timestamptz,
      -- ISO-8601 day numbers, 1 = Monday. Empty means every day, which is the
      -- right reading of "the restaurant did not restrict this" — the same
      -- empty-means-everything rule the licence's `modes[]` follows.
      days_of_week       smallint[]  NOT NULL DEFAULT '{}',
      -- A window that crosses midnight is legitimate and common: 22:00–02:00 is
      -- a late-night offer, so these are deliberately NOT constrained to
      -- from < to.
      time_from          time,
      time_to            time,
      requires_customer  boolean     NOT NULL DEFAULT false,
      requires_manager   boolean     NOT NULL DEFAULT false,
      -- Not offered in the ordinary list; a person has to hold
      -- `discount.apply_restricted` to see it at all.
      is_restricted      boolean     NOT NULL DEFAULT false,
      is_active          boolean     NOT NULL DEFAULT true,
      -- Optimistic concurrency, as the catalogue already has: two managers
      -- editing one discount over the LAN must not silently overwrite each
      -- other.
      revision           integer     NOT NULL DEFAULT 1,
      created_at         timestamptz NOT NULL DEFAULT now(),
      updated_at         timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_discounts_kind_known CHECK (kind IN ('percentage', 'fixed')),
      CONSTRAINT pos_discounts_scope_known CHECK (scope IN ('order', 'item')),
      -- Exactly one value column, and it must be the one the kind names. A
      -- percentage discount carrying a fixed amount is a row nothing can price.
      CONSTRAINT pos_discounts_value_matches_kind CHECK (
        (kind = 'percentage' AND value_bp IS NOT NULL AND value_minor IS NULL)
        OR
        (kind = 'fixed' AND value_minor IS NOT NULL AND value_bp IS NULL)),
      CONSTRAINT pos_discounts_value_sane CHECK (
        (value_bp IS NULL OR (value_bp > 0 AND value_bp <= 10000))
        AND (value_minor IS NULL OR value_minor > 0)),
      CONSTRAINT pos_discounts_limits_sane CHECK (
        (min_order_minor IS NULL OR min_order_minor >= 0)
        AND (max_discount_minor IS NULL OR max_discount_minor > 0)),
      CONSTRAINT pos_discounts_window_sane CHECK (
        starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at),
      CONSTRAINT pos_discounts_code_unique UNIQUE (restaurant_id, code)
    )
    ''',
    // A `smallint[]` cannot be range-checked by a column CHECK, so the
    // constraint is written over the unnested array.
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_discounts ADD CONSTRAINT pos_discounts_days_are_days CHECK (
        days_of_week <@ ARRAY[1,2,3,4,5,6,7]::smallint[]);
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_discounts_offered_idx
      ON pos_discounts (restaurant_id, scope, is_active)
    ''',

    // What a discount applies to. No rows for a discount means it applies to
    // everything — the same empty-means-everything reading as `days_of_week`,
    // and the reason this is a table rather than three nullable columns.
    '''
    CREATE TABLE IF NOT EXISTS pos_discount_targets (
      discount_id bigint NOT NULL REFERENCES pos_discounts(id) ON DELETE CASCADE,
      target_type text   NOT NULL,
      -- text, not bigint: a category and a product are ids, an order type is a
      -- wire name (`dine_in`). One column that holds all three beats three
      -- columns of which two are always null.
      target_id   text   NOT NULL,
      CONSTRAINT pos_discount_targets_type_known
        CHECK (target_type IN ('category', 'product', 'order_type')),
      PRIMARY KEY (discount_id, target_type, target_id)
    )
    ''',

    // What was actually taken off, and by whom.
    //
    // **Every descriptive column here is a snapshot.** `discount_id` is kept
    // for reporting, and is deliberately NOT a foreign key with a cascade: a
    // restaurant retiring a promotion must not take the record of what it gave
    // away with it. Same argument as `pos_audit_events` carrying no keys.
    '''
    CREATE TABLE IF NOT EXISTS pos_order_discounts (
      id             bigserial   PRIMARY KEY,
      order_id       bigint      NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
      -- NULL means the whole order. That distinction is load-bearing on screen
      -- as well as in the ledger: a line discount renders inside its line in
      -- the cart, an order discount renders in the totals block.
      order_line_id  bigint      REFERENCES pos_order_lines(id) ON DELETE CASCADE,
      discount_id    bigint,
      name_snapshot  text        NOT NULL,
      kind           text        NOT NULL,
      value_bp       integer,
      value_minor    bigint,
      -- What it actually came to, after any cap. This is the number that
      -- reduces the bill; the value above is only how it was worked out.
      amount_minor   bigint      NOT NULL,
      reason_id      bigint,
      note           text,
      applied_by     bigint      NOT NULL,
      -- Set when the discount was above the applier's limit and a supervisor
      -- lent the permission. Both people on the row, as everywhere else.
      approved_by_id bigint,
      applied_at     timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_order_discounts_kind_known CHECK (kind IN ('percentage', 'fixed')),
      CONSTRAINT pos_order_discounts_amount_positive CHECK (amount_minor > 0)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_order_discounts_order_idx
      ON pos_order_discounts (order_id)
    ''',
    // "Every discount this person gave last month" is the report that makes the
    // permission worth having.
    '''
    CREATE INDEX IF NOT EXISTS pos_order_discounts_applier_idx
      ON pos_order_discounts (applied_by, applied_at DESC)
    ''',

    // The total taken off the order, stored beside the other totals.
    //
    // Derivable by summing `pos_order_discounts`, and stored anyway, for the
    // same reason `pos_shifts.variance_minor` is: it is a number that appears
    // on a receipt somebody kept, and recomputing it later from rows that may
    // have moved on would quietly rewrite what the customer was told.
    'ALTER TABLE pos_orders ADD COLUMN IF NOT EXISTS discount_minor bigint NOT NULL DEFAULT 0',
    // A discount bigger than the goods is not a discount, it is a negative
    // sale. The database refuses to hold one.
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_orders ADD CONSTRAINT pos_orders_discount_sane
        CHECK (discount_minor >= 0 AND discount_minor <= subtotal_minor);
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',

    // How much a role may take off by hand, before a supervisor is needed.
    //
    // **Interim, and named as such.** Wave C moves these into
    // `pos_permission_limits`, which can express a limit per person as well as
    // per role, and can carry the refund ceilings too. They live here now
    // because the discount feature needs a ceiling to enforce and a screen
    // cannot wait for a permission-model rewrite to have one.
    //
    // NULL means **unlimited**, not zero. Reading a missing cap as zero would
    // leave every existing role — including the owner's — unable to discount
    // anything the moment this migration ran.
    'ALTER TABLE pos_roles ADD COLUMN IF NOT EXISTS max_discount_bp integer',
    'ALTER TABLE pos_roles ADD COLUMN IF NOT EXISTS max_discount_minor bigint',
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_roles ADD CONSTRAINT pos_roles_discount_limits_sane CHECK (
        (max_discount_bp IS NULL OR (max_discount_bp >= 0 AND max_discount_bp <= 10000))
        AND (max_discount_minor IS NULL OR max_discount_minor >= 0));
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',
  ]),
];

/// Brings the branch database up to the current schema.
///
/// Safe to call from every till on every launch: the advisory lock serialises
/// concurrent runners and `schema_migrations` makes each step run once.
class PosMigrator {
  const PosMigrator(this._db, {this.migrations = posMigrations});

  final PosDatabase _db;
  final List<PosMigration> migrations;

  /// Returns the versions actually applied by *this* call.
  Future<List<int>> migrate(
    DeploymentConfig config,
  ) async => _db.runTx(config, (tx) async {
    // Held for the length of the transaction and released on commit, so a
    // till that crashes mid-migration does not wedge the branch.
    await tx.execute('SELECT pg_advisory_xact_lock($_migrationLockKey)');

    await tx.execute('''
          CREATE TABLE IF NOT EXISTS schema_migrations (
            version    integer     PRIMARY KEY,
            applied_at timestamptz NOT NULL DEFAULT now()
          )
        ''');

    final existing = await tx.execute('SELECT version FROM schema_migrations');
    final applied = existing.map((row) => row[0] as int).toSet();

    final ran = <int>[];
    for (final migration in migrations) {
      if (applied.contains(migration.version)) continue;
      for (final statement in migration.statements) {
        await tx.execute(statement);
      }
      await tx.execute(
        Sql.named('INSERT INTO schema_migrations (version) VALUES (@version)'),
        parameters: {'version': migration.version},
      );
      ran.add(migration.version);
    }
    return ran;
  });
}
