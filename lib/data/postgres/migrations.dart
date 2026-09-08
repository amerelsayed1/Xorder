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
  // An order that cannot say who sold it is one nobody can question. Until now
  // the only person on a `pos_orders` row was whoever *voided* it — the record
  // named the exception and not the sale.
  //
  // `shift_id` is not an answer to this. It names the drawer, and a drawer is
  // worked by more than one person; on a two-cashier shift, attributing every
  // sale to whoever opened the till is not a smaller truth, it is a wrong one.
  //
  // Three things need this before they can be built: order history (§90) lists
  // the seller, a refund (§18) is issued against a sale somebody made, and
  // sales-by-staff (§59) is a report with no subject without it.
  PosMigration(11, 'who sold it', [
    // Nullable, because every order already written was written without one and
    // there is nobody to backfill them with. An honest blank beats a name
    // chosen by a query.
    //
    // RESTRICT, like `voided_by` and `pos_shifts.opened_by`: deleting a member
    // of staff must never delete the record of what they sold.
    '''
    ALTER TABLE pos_orders
      ADD COLUMN IF NOT EXISTS served_by bigint REFERENCES pos_staff(id) ON DELETE RESTRICT
    ''',
    // History is read one branch at a time, newest first, which is neither of
    // the indexes this table already has: the unique key on the invoice is
    // useless without a number to look up, and `pos_orders_status_idx` only
    // helps when a status filter is set.
    '''
    CREATE INDEX IF NOT EXISTS pos_orders_history_idx
      ON pos_orders (restaurant_id, branch_id, occurred_at DESC)
    ''',
    // Partial, because most orders have no seller yet and an index over a
    // column that is mostly NULL is mostly wasted pages.
    '''
    CREATE INDEX IF NOT EXISTS pos_orders_served_by_idx
      ON pos_orders (restaurant_id, served_by, occurred_at DESC)
      WHERE served_by IS NOT NULL
    ''',
  ]),
  // Money going back out of the drawer.
  //
  // Three tables and four rules, and the rules live here rather than in Dart
  // for the reason the whole schema does: a till is not the only thing that can
  // write to this database, and "we always call the repository" is a promise
  // nobody can keep across a psql prompt, a sync path and a build from next
  // year.
  //
  // The rules:
  //
  //  1. A line cannot be refunded more times than it was sold. Held by the
  //     `refunded_quantity` counter migration 9 already constrained to
  //     `<= quantity` — this migration adds the trigger that maintains it.
  //  2. An order cannot give back more than it took. Same shape: a
  //     `refunded_minor` counter with a CHECK against `total_minor`.
  //  3. A refund line must belong to the order being refunded. Not in the
  //     original plan; it is the one that would otherwise let a mistyped id
  //     refund somebody else's food.
  //  4. A refund says where the money went, and the tender adds up to the
  //     refund. Deferred to commit, because the payments are inserted after
  //     the refund they belong to.
  PosMigration(12, 'refunds — money going back, and the record of it', [
    // The counter, not a SUM over `pos_refunds`. It is the number the *next*
    // refund has to check, inside the same transaction, under the same row
    // lock — recomputing it from another table is how an order gets refunded
    // twice at two tills.
    '''
    ALTER TABLE pos_orders
      ADD COLUMN IF NOT EXISTS refunded_minor bigint NOT NULL DEFAULT 0
    ''',
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_orders ADD CONSTRAINT pos_orders_refunded_within_taken CHECK (
        refunded_minor >= 0 AND refunded_minor <= total_minor);
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',

    // RESTRICT on the order: deleting a sale must never orphan the record of
    // money given back against it.
    //
    // `reason_id` is nullable, which is a deliberate departure from the plan's
    // NOT NULL. §18 lists `refund.reason_required` as a *setting* with a
    // default of true — a NOT NULL column would make the off position
    // unimplementable, and a database that forbids a configuration the
    // specification permits is a database that will be worked around. The
    // policy is enforced in `RefundPolicy`, where it can be configured.
    '''
    CREATE TABLE IF NOT EXISTS pos_refunds (
      id                bigserial    PRIMARY KEY,
      client_refund_id  uuid         NOT NULL,
      restaurant_id     bigint       NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id         bigint       NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      terminal_id       uuid         NOT NULL,
      order_id          bigint       NOT NULL REFERENCES pos_orders(id) ON DELETE RESTRICT,
      shift_id          bigint       REFERENCES pos_shifts(id) ON DELETE SET NULL,
      business_day_id   bigint,
      kind              text         NOT NULL,
      subtotal_minor    bigint       NOT NULL,
      discount_minor    bigint       NOT NULL DEFAULT 0,
      service_minor     bigint       NOT NULL,
      vat_minor         bigint       NOT NULL,
      total_minor       bigint       NOT NULL,
      reason_id         bigint       REFERENCES pos_reason_codes(id) ON DELETE RESTRICT,
      note              text,
      refunded_by       bigint       NOT NULL REFERENCES pos_staff(id) ON DELETE RESTRICT,
      approved_by_id    bigint       REFERENCES pos_staff(id) ON DELETE RESTRICT,
      occurred_at       timestamptz  NOT NULL DEFAULT now(),
      -- Idempotency, exactly as an order has it. A till that retries after a
      -- timeout gets the original refund back, never a second one.
      CONSTRAINT pos_refunds_client_id_unique
        UNIQUE (restaurant_id, client_refund_id),
      CONSTRAINT pos_refunds_kind_known CHECK (kind IN ('full', 'partial')),
      -- A refund of nothing is not a refund. It is a row somebody would write
      -- to make a reason code appear against an order without giving anything
      -- back.
      CONSTRAINT pos_refunds_total_positive CHECK (total_minor > 0),
      CONSTRAINT pos_refunds_parts_sane CHECK (
        subtotal_minor >= 0 AND discount_minor >= 0
        AND service_minor >= 0 AND vat_minor >= 0)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS pos_refunds_order_idx ON pos_refunds (order_id)',
    '''
    CREATE INDEX IF NOT EXISTS pos_refunds_history_idx
      ON pos_refunds (restaurant_id, branch_id, occurred_at DESC)
    ''',

    // RESTRICT on the order line for the same reason as the order: the line is
    // what the counter hangs off, and losing it would leave a quantity nothing
    // can explain.
    '''
    CREATE TABLE IF NOT EXISTS pos_refund_lines (
      id               bigserial  PRIMARY KEY,
      refund_id        bigint     NOT NULL REFERENCES pos_refunds(id) ON DELETE CASCADE,
      order_line_id    bigint     NOT NULL REFERENCES pos_order_lines(id) ON DELETE RESTRICT,
      quantity         integer    NOT NULL,
      unit_price_minor bigint     NOT NULL,
      line_total_minor bigint     NOT NULL,
      -- The name as it was sold, again. A dish renamed in March must not
      -- rewrite what a refund receipt said in January.
      name_snapshot    text       NOT NULL,
      CONSTRAINT pos_refund_lines_quantity_positive CHECK (quantity > 0),
      CONSTRAINT pos_refund_lines_prices_sane
        CHECK (unit_price_minor >= 0 AND line_total_minor >= 0),
      -- One row per line per refund. Two rows for the same line inside one
      -- refund would still total correctly and would make the receipt
      -- unreadable.
      CONSTRAINT pos_refund_lines_once_per_refund UNIQUE (refund_id, order_line_id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_refund_lines_order_line_idx
      ON pos_refund_lines (order_line_id)
    ''',

    '''
    CREATE TABLE IF NOT EXISTS pos_refund_payments (
      id             bigserial    PRIMARY KEY,
      refund_id      bigint       NOT NULL REFERENCES pos_refunds(id) ON DELETE CASCADE,
      tender_type_id bigint       NOT NULL,
      label          text         NOT NULL,
      amount_minor   bigint       NOT NULL,
      reference      varchar(80),
      occurred_at    timestamptz  NOT NULL DEFAULT now(),
      CONSTRAINT pos_refund_payments_amount_positive CHECK (amount_minor > 0)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_refund_payments_refund_idx
      ON pos_refund_payments (refund_id)
    ''',

    // ── The triggers that hold the counters ──────────────────────────────
    //
    // SECURITY DEFINER, and the till is deliberately NOT granted UPDATE on
    // either counter. The effect is that `refunded_quantity` and
    // `refunded_minor` can only move by inserting a refund row: the counter
    // and the record it summarises cannot disagree, because there is no way to
    // write one without the other.
    //
    // `search_path` is pinned. A SECURITY DEFINER function that resolves its
    // own table names through a caller-controlled search path is the textbook
    // privilege-escalation hole.
    '''
    CREATE OR REPLACE FUNCTION pos_refund_applied() RETURNS trigger
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS \$fn\$
    DECLARE
      sold pos_orders%ROWTYPE;
    BEGIN
      -- FOR UPDATE, so two tills refunding the same order queue rather than
      -- both reading a stale `refunded_minor` and both being allowed.
      SELECT * INTO sold FROM pos_orders WHERE id = NEW.order_id FOR UPDATE;

      IF sold.restaurant_id <> NEW.restaurant_id
         OR sold.branch_id <> NEW.branch_id THEN
        RAISE EXCEPTION
          'a refund must belong to the same branch as the order it refunds';
      END IF;

      -- Money that never arrived cannot go back. A voided order took nothing;
      -- a fully refunded one has nothing left.
      IF sold.status NOT IN ('PAID', 'CLOSED', 'PARTIALLY_REFUNDED') THEN
        RAISE EXCEPTION 'order % is %, so there is nothing to refund',
          sold.id, sold.status;
      END IF;

      UPDATE pos_orders
         SET refunded_minor = refunded_minor + NEW.total_minor,
             -- Derived from the counter rather than passed in, so the status
             -- and the money can never drift apart.
             status = CASE
               WHEN refunded_minor + NEW.total_minor >= total_minor
                 THEN 'REFUNDED' ELSE 'PARTIALLY_REFUNDED' END,
             status_changed_at = NEW.occurred_at
       WHERE id = NEW.order_id;

      RETURN NEW;
    END \$fn\$
    ''',
    'DROP TRIGGER IF EXISTS pos_refunds_apply ON pos_refunds',
    '''
    CREATE TRIGGER pos_refunds_apply AFTER INSERT ON pos_refunds
      FOR EACH ROW EXECUTE FUNCTION pos_refund_applied()
    ''',

    '''
    CREATE OR REPLACE FUNCTION pos_refund_line_applied() RETURNS trigger
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS \$fn\$
    BEGIN
      -- The `order_id` clause is the point. Without it a mistyped line id
      -- refunds a quantity off somebody else's order, and every total still
      -- adds up.
      UPDATE pos_order_lines
         SET refunded_quantity = refunded_quantity + NEW.quantity
       WHERE id = NEW.order_line_id
         AND order_id = (SELECT order_id FROM pos_refunds WHERE id = NEW.refund_id);

      IF NOT FOUND THEN
        RAISE EXCEPTION
          'refund line % does not belong to the order being refunded',
          NEW.order_line_id;
      END IF;

      RETURN NEW;
    END \$fn\$
    ''',
    'DROP TRIGGER IF EXISTS pos_refund_lines_apply ON pos_refund_lines',
    '''
    CREATE TRIGGER pos_refund_lines_apply AFTER INSERT ON pos_refund_lines
      FOR EACH ROW EXECUTE FUNCTION pos_refund_line_applied()
    ''',

    // Deferred to commit: the payments are inserted after the refund they
    // belong to, so an immediate check would refuse every refund ever written.
    '''
    CREATE OR REPLACE FUNCTION pos_refund_tender_balances() RETURNS trigger
      LANGUAGE plpgsql AS \$fn\$
    DECLARE
      tendered bigint;
    BEGIN
      SELECT COALESCE(SUM(amount_minor), 0) INTO tendered
        FROM pos_refund_payments WHERE refund_id = NEW.id;

      IF tendered <> NEW.total_minor THEN
        RAISE EXCEPTION
          'refund % is %, but % was tendered back — a refund that does not foot is one nobody can reconcile against a drawer',
          NEW.id, NEW.total_minor, tendered;
      END IF;

      RETURN NEW;
    END \$fn\$
    ''',
    'DROP TRIGGER IF EXISTS pos_refunds_tendered_in_full ON pos_refunds',
    '''
    CREATE CONSTRAINT TRIGGER pos_refunds_tendered_in_full
      AFTER INSERT ON pos_refunds
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION pos_refund_tender_balances()
    ''',

    // The refund reasons §18 asks for. Seeded like migration 9's, and only
    // where the restaurant has none — a restaurant that has edited its list
    // must not have this build's opinion pushed back over it.
    '''
    INSERT INTO pos_reason_codes (restaurant_id, scope, code, name_en, name_ar, sort_order)
    SELECT r.id, v.scope, v.code, v.name_en, v.name_ar, v.sort_order
      FROM pos_restaurants r
     CROSS JOIN (VALUES
       ('refund', 'customer_unhappy', 'Customer not happy', 'العميل غير راضٍ', 1),
       ('refund', 'wrong_item',       'Wrong item served',  'صنف خاطئ',        2),
       ('refund', 'quality',          'Quality problem',    'مشكلة في الجودة', 3),
       ('refund', 'overcharged',      'Overcharged',        'حُوسب بالزيادة',  4),
       ('refund', 'order_cancelled',  'Order cancelled',    'أُلغي الطلب',     5)
     ) AS v(scope, code, name_en, name_ar, sort_order)
     WHERE NOT EXISTS (
       SELECT 1 FROM pos_reason_codes existing
        WHERE existing.restaurant_id = r.id AND existing.scope = 'refund')
    ''',
  ]),
  // The owner role must hold every capability. It is stated in
  // `SystemRoles.owner`, enforced by `RolesRepository.save`, and was true of
  // every database at the moment it was seeded — and then Wave A added
  // `order.item.delete_before_send`, `order.item.delete_after_send` and
  // `order.view_all`, and every branch server seeded before that kept an owner
  // who could not grant them.
  //
  // That is the exact failure the invariant exists to prevent: a restaurant
  // reaching a state where nobody can grant a capability nobody holds.
  //
  // **Additive, never subtractive.** The union leaves anything a restaurant
  // configured for itself alone, and re-running adds nothing. Only the *owner*
  // is touched: manager, supervisor and cashier are defaults a restaurant
  // edits, and pushing this build's opinion back over an edited role is the
  // thing migration 12's reason seed was careful not to do.
  //
  // The list is a frozen literal, not an interpolation of `PosCapability.all`.
  // An applied migration is history, and history that changes when a Dart
  // constant is edited is not history. A capability added after this needs its
  // own migration — which is the point: somebody has to think about it.
  PosMigration(13, 'the owner role holds every capability Wave A added', [
    '''
    UPDATE pos_roles
       SET capabilities = ARRAY(
             SELECT DISTINCT unnest(
               capabilities || ARRAY[
                 'order.item.delete_before_send',
                 'order.item.delete_after_send',
                 'order.view_all'
               ]::text[]))
     WHERE code = 'owner'
       AND NOT (capabilities @> ARRAY[
         'order.item.delete_before_send',
         'order.item.delete_after_send',
         'order.view_all'
       ]::text[])
    ''',
  ]),
  // Wave B's foundation: what the restaurant has configured, what is in the
  // drawer, and which trading day a sale belongs to.
  //
  // The settings table lands here rather than in Wave D on purpose. Blind
  // close, the business-day start time and the refund policy are all settings,
  // and hard-coding them now means moving them twice.
  PosMigration(14, 'settings, cash movements and the business day', [
    // Scoped key/value, read as a whole and parsed by typed accessors in Dart.
    //
    // `scope_id` is NOT NULL with an empty-string default rather than nullable,
    // because PostgreSQL treats NULLs as distinct in a UNIQUE constraint — a
    // nullable column here would happily accept the same restaurant-level key
    // twice, and the second write would silently not be an update.
    //
    // `value` is text, not jsonb. Every reader is a typed accessor that knows
    // what shape it wants ('06:00', 'true', '15000'), and a jsonb column would
    // add a parse step on both sides to buy type checking nothing performs.
    '''
    CREATE TABLE IF NOT EXISTS pos_settings (
      id            bigserial   PRIMARY KEY,
      restaurant_id bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      scope         text        NOT NULL,
      scope_id      text        NOT NULL DEFAULT '',
      key           text        NOT NULL,
      value         text        NOT NULL,
      updated_at    timestamptz NOT NULL DEFAULT now(),
      updated_by    bigint      REFERENCES pos_staff(id) ON DELETE SET NULL,
      CONSTRAINT pos_settings_scope_known
        CHECK (scope IN ('restaurant', 'branch', 'terminal')),
      -- A restaurant-scoped row names no scope; a narrower one must.
      CONSTRAINT pos_settings_scope_id_present CHECK (
        (scope = 'restaurant' AND scope_id = '')
        OR (scope <> 'restaurant' AND scope_id <> '')),
      CONSTRAINT pos_settings_unique_key
        UNIQUE (restaurant_id, scope, scope_id, key)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_settings_lookup_idx
      ON pos_settings (restaurant_id, key)
    ''',

    // A drawer is a physical thing. Most tills have one and it is theirs, which
    // is why `terminal_id` is nullable — a shared drawer at a service counter
    // belongs to the branch, not to a machine.
    '''
    CREATE TABLE IF NOT EXISTS pos_cash_drawers (
      id            bigserial   PRIMARY KEY,
      restaurant_id bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id     bigint      NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      terminal_id   uuid        REFERENCES pos_terminals(id) ON DELETE SET NULL,
      name          text        NOT NULL,
      is_active     boolean     NOT NULL DEFAULT true,
      created_at    timestamptz NOT NULL DEFAULT now()
    )
    ''',

    // The trading day, which is not the calendar day. A restaurant that closes
    // at 2 a.m. takes money on Saturday that belongs to Friday's takings, and
    // `day.start_time` is what decides. Resolved once when the order is
    // written and stored — never derived at read time, because the offset is a
    // setting somebody can change and a report that re-derived it would
    // silently re-date history.
    '''
    CREATE TABLE IF NOT EXISTS pos_business_days (
      id            bigserial   PRIMARY KEY,
      restaurant_id bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id     bigint      NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      business_date date        NOT NULL,
      opened_at     timestamptz NOT NULL DEFAULT now(),
      opened_by     bigint      REFERENCES pos_staff(id) ON DELETE RESTRICT,
      closed_at     timestamptz,
      closed_by     bigint      REFERENCES pos_staff(id) ON DELETE RESTRICT,
      -- Closed over the top of blockers. The reason is not optional when it is.
      forced        boolean     NOT NULL DEFAULT false,
      force_reason  text,
      gross_minor   bigint,
      net_minor     bigint,
      CONSTRAINT pos_business_days_unique
        UNIQUE (restaurant_id, branch_id, business_date),
      CONSTRAINT pos_business_days_closed_is_complete CHECK (
        (closed_at IS NULL AND closed_by IS NULL)
        OR (closed_at IS NOT NULL AND closed_by IS NOT NULL)),
      -- A forced close with no reason is the row somebody would want to leave.
      CONSTRAINT pos_business_days_force_is_explained CHECK (
        NOT forced OR (force_reason IS NOT NULL AND force_reason <> ''))
    )
    ''',
    // One open day per branch, held by the database rather than by a query
    // somebody remembers to run. Two open days is two sets of takings for one
    // evening, and nothing downstream could tell which was which.
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_business_days_one_open
      ON pos_business_days (restaurant_id, branch_id)
      WHERE closed_at IS NULL
    ''',

    // Money into and out of the drawer that is not a sale.
    //
    // **Amounts are always positive and the `kind` carries the direction.** A
    // pay-out stored as a negative amount under `kind = 'pay_out'` would be
    // negated twice by anything that reads the kind, and the two conventions
    // would coexist for exactly as long as it took somebody to write the second
    // reader.
    '''
    CREATE TABLE IF NOT EXISTS pos_cash_movements (
      id              bigserial   PRIMARY KEY,
      restaurant_id   bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id       bigint      NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      terminal_id     uuid        NOT NULL,
      drawer_id       bigint      REFERENCES pos_cash_drawers(id) ON DELETE SET NULL,
      -- NOT NULL, unlike an order's. Cash cannot move without an open drawer,
      -- and a movement nobody can attribute to a shift is one nothing can
      -- reconcile.
      shift_id        bigint      NOT NULL REFERENCES pos_shifts(id) ON DELETE RESTRICT,
      business_day_id bigint,
      kind            text        NOT NULL,
      amount_minor    bigint      NOT NULL DEFAULT 0,
      reason_id       bigint      REFERENCES pos_reason_codes(id) ON DELETE RESTRICT,
      note            text,
      staff_id        bigint      NOT NULL REFERENCES pos_staff(id) ON DELETE RESTRICT,
      approved_by_id  bigint      REFERENCES pos_staff(id) ON DELETE RESTRICT,
      occurred_at     timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_cash_movements_kind_known CHECK (kind IN (
        'pay_in', 'pay_out', 'drawer_open', 'float_adjust')),
      -- Opening the drawer moves nothing. Everything else moves something.
      --
      -- Written as a CASE rather than as the plan's
      -- `(kind = 'drawer_open' AND amount_minor = 0) OR amount_minor > 0`,
      -- which does not say that: a `drawer_open` carrying 100 fails the first
      -- clause, passes the second, and is accepted. The first test written
      -- against this caught it.
      CONSTRAINT pos_cash_movements_amount_matches_kind CHECK (
        CASE WHEN kind = 'drawer_open'
             THEN amount_minor = 0
             ELSE amount_minor > 0 END)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_cash_movements_shift_idx
      ON pos_cash_movements (shift_id, occurred_at)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_cash_movements_day_idx
      ON pos_cash_movements (restaurant_id, branch_id, occurred_at DESC)
    ''',

    // The late foreign keys. `business_day_id` has been a bare bigint on orders
    // since migration 9 and on refunds since migration 12, precisely so that
    // those writes could stamp it from the day this table existed rather than
    // needing a backfill of rows nobody can re-date.
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_orders ADD CONSTRAINT pos_orders_business_day_fk
        FOREIGN KEY (business_day_id) REFERENCES pos_business_days(id)
        ON DELETE RESTRICT;
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_refunds ADD CONSTRAINT pos_refunds_business_day_fk
        FOREIGN KEY (business_day_id) REFERENCES pos_business_days(id)
        ON DELETE RESTRICT;
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',
    '''
    ALTER TABLE pos_shifts ADD COLUMN IF NOT EXISTS business_day_id bigint
      REFERENCES pos_business_days(id) ON DELETE RESTRICT
    ''',
    // §26: a shift opened over a refusal — outside hours, or a second shift on
    // one drawer — names who allowed it.
    '''
    ALTER TABLE pos_shifts ADD COLUMN IF NOT EXISTS opened_with_approval_by bigint
      REFERENCES pos_staff(id) ON DELETE RESTRICT
    ''',

    // The reasons a pay-in and a pay-out pick from. Migration 9 provisioned
    // both scopes and seeded neither; §22 needs them now. Only where the
    // restaurant has none, for the same reason migration 12's refund reasons
    // are: a restaurant that has edited its list must not have this build's
    // opinion pushed back over it.
    '''
    INSERT INTO pos_reason_codes (restaurant_id, scope, code, name_en, name_ar, sort_order)
    SELECT r.id, v.scope, v.code, v.name_en, v.name_ar, v.sort_order
      FROM pos_restaurants r
     CROSS JOIN (VALUES
       ('pay_in',  'float_top_up',  'Float top-up',      'تعزيز العهدة',      1),
       ('pay_in',  'owner_deposit', 'Owner deposit',     'إيداع من المالك',   2),
       ('pay_in',  'correction',    'Correcting a count','تصحيح جرد',         3),
       ('pay_out', 'supplier',      'Supplier payment',  'دفعة لمورّد',       1),
       ('pay_out', 'petty_expense', 'Petty expense',     'مصروف نثري',        2),
       ('pay_out', 'staff_advance', 'Staff advance',     'سلفة موظف',         3),
       ('pay_out', 'bank_drop',     'Bank drop',         'توريد للبنك',       4),
       ('pay_out', 'correction',    'Correcting a count','تصحيح جرد',         5)
     ) AS v(scope, code, name_en, name_ar, sort_order)
     WHERE NOT EXISTS (
       SELECT 1 FROM pos_reason_codes existing
        WHERE existing.restaurant_id = r.id AND existing.scope = v.scope)
    ''',
  ]),
  // Wave B's five keys, on the owner role.
  //
  // Migration 13 said this would be needed again: *"a capability added after
  // this needs its own migration — which is the point, because somebody has to
  // think about it."* This is that migration, and the thinking is that a
  // supervisor may see the expected drawer and the variance, an owner may force
  // a day closed, and neither is a default anybody inherits by accident.
  //
  // Same shape as 13: additive union, idempotent, owner only, frozen literals.
  PosMigration(15, 'the owner role holds the capabilities Wave B added', [
    '''
    UPDATE pos_roles
       SET capabilities = ARRAY(
             SELECT DISTINCT unnest(
               capabilities || ARRAY[
                 'cash.open_without_sale',
                 'shift.view_expected_cash',
                 'cash.variance.view',
                 'day.close',
                 'day.force_close'
               ]::text[]))
     WHERE code = 'owner'
       AND NOT (capabilities @> ARRAY[
         'cash.open_without_sale',
         'shift.view_expected_cash',
         'cash.variance.view',
         'day.close',
         'day.force_close'
       ]::text[])
    ''',
    // §22 and §24 named the same question twice. `PosCapability.canonical`
    // folds the duplicate on read; this folds it in storage, so a role editor
    // does not show a checkbox for a key the code has stopped believing in.
    '''
    UPDATE pos_roles
       SET capabilities = ARRAY(
             SELECT DISTINCT unnest(
               array_remove(capabilities, 'cash.view_expected')
               || ARRAY['shift.view_expected_cash']::text[]))
     WHERE 'cash.view_expected' = ANY(capabilities)
    ''',
  ]),
  // Tax as a breakdown rather than a single figure.
  //
  // The risk register promised this in v1 — *"the money model carries a
  // `tax_lines[]` breakdown from day one so a compliance layer has something to
  // attach to"* — and nothing was built. `pos_orders.vat_minor` is one number
  // with no rate behind it, which cannot express a zero-rated bottle of water
  // beside a standard-rated meal, and cannot produce the per-rate breakdown
  // Egypt's ETA e-receipt requires.
  //
  // It lands **before** anything is filed, because a tax breakdown cannot be
  // retrofitted onto orders already sent to a tax authority.
  PosMigration(16, 'tax groups, and the tax breakdown a filing needs', [
    '''
    CREATE TABLE IF NOT EXISTS pos_tax_groups (
      id            bigserial   PRIMARY KEY,
      restaurant_id bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      name_en       text        NOT NULL,
      name_ar       text,
      -- Basis points, like every other rate in this schema. 1400 = 14%.
      rate_bp       integer     NOT NULL,
      -- Exactly one per restaurant, enforced below. It is what a product with
      -- no group of its own is charged at.
      is_default    boolean     NOT NULL DEFAULT false,
      is_active     boolean     NOT NULL DEFAULT true,
      created_at    timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_tax_groups_rate_sane
        CHECK (rate_bp >= 0 AND rate_bp <= 10000),
      CONSTRAINT pos_tax_groups_name_unique UNIQUE (restaurant_id, name_en)
    )
    ''',
    // One default, held by the database. Two would make "what does an
    // unclassified product cost" a question with two answers.
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_tax_groups_one_default
      ON pos_tax_groups (restaurant_id) WHERE is_default
    ''',

    // Nullable: "nobody has said" and "somebody chose the standard rate" are
    // different facts. The first follows the restaurant if it changes its
    // default; the second does not.
    '''
    ALTER TABLE pos_products ADD COLUMN IF NOT EXISTS tax_group_id bigint
      REFERENCES pos_tax_groups(id) ON DELETE SET NULL
    ''',

    // The breakdown itself. One row per **rate** per order, not per line: tax
    // is filed by rate, and rounding once per rate is what keeps a ticket's
    // arithmetic identical to what it was when every product shared one.
    //
    // `name_snapshot` and `rate_bp` are snapshots for the same reason a line's
    // name is: a restaurant that renames "VAT 14%" or is moved to 15% next year
    // must not rewrite what a receipt said today.
    '''
    CREATE TABLE IF NOT EXISTS pos_order_taxes (
      id            bigserial PRIMARY KEY,
      order_id      bigint    NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
      tax_group_id  bigint    REFERENCES pos_tax_groups(id) ON DELETE SET NULL,
      name_snapshot text      NOT NULL,
      rate_bp       integer   NOT NULL,
      base_minor    bigint    NOT NULL,
      amount_minor  bigint    NOT NULL,
      CONSTRAINT pos_order_taxes_sane CHECK (
        rate_bp >= 0 AND rate_bp <= 10000
        AND base_minor >= 0 AND amount_minor >= 0),
      -- One row per rate per order. A second row for the same rate would be a
      -- breakdown that does not break anything down.
      CONSTRAINT pos_order_taxes_one_per_rate UNIQUE (order_id, rate_bp, name_snapshot)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_order_taxes_order_idx
      ON pos_order_taxes (order_id)
    ''',

    // Every restaurant gets the rate it has been charging all along, named.
    //
    // Read out of `pos_money_config`'s payload where one exists, so a branch on
    // 15% keeps 15% — reverting it to Egypt's headline 14% would change what
    // customers are charged, which a migration must never do. The path matches
    // `MoneyConfigCodec`: the first entry of `tax_rules` carrying a `rate_bp`.
    '''
    INSERT INTO pos_tax_groups (restaurant_id, name_en, name_ar, rate_bp, is_default)
    SELECT r.id, 'VAT', 'ضريبة القيمة المضافة',
           COALESCE(
             (SELECT (m.payload -> 'tax_rules' -> 0 ->> 'rate_bp')::integer
                FROM pos_money_config m
               WHERE m.restaurant_id = r.id
                 AND jsonb_typeof(m.payload -> 'tax_rules') = 'array'
                 AND jsonb_array_length(m.payload -> 'tax_rules') > 0),
             1400),
           true
      FROM pos_restaurants r
     WHERE NOT EXISTS (
       SELECT 1 FROM pos_tax_groups g WHERE g.restaurant_id = r.id)
    ''',

    // Backfill the breakdown for orders that already exist.
    //
    // One line each, at the restaurant's default rate, based on whatever the
    // order actually charged. It is not a reconstruction of what the rate *was*
    // — nothing recorded that — but it is the honest statement that this much
    // tax was taken, and it means no order is missing a breakdown entirely.
    '''
    INSERT INTO pos_order_taxes (order_id, tax_group_id, name_snapshot, rate_bp,
                                 base_minor, amount_minor)
    SELECT o.id, g.id, g.name_en, g.rate_bp,
           GREATEST(o.subtotal_minor - o.discount_minor + o.service_minor, 0),
           o.vat_minor
      FROM pos_orders o
      JOIN pos_tax_groups g
        ON g.restaurant_id = o.restaurant_id AND g.is_default
     WHERE o.vat_minor > 0
       AND NOT EXISTS (
         SELECT 1 FROM pos_order_taxes t WHERE t.order_id = o.id)
    ''',
  ]),
  // What a branch charges, and what a modifier group allows.
  //
  // Two menu gaps the market treats as table stakes and this schema could not
  // express: delivery prices differing from dine-in (Foodics calls these
  // Location Rules), and the modifier economics every competitor ships — free
  // allowances, pre-selected defaults, a minimum selection.
  PosMigration(17, 'per-branch and per-channel prices, modifier economics', [
    // One row per product per (branch, order type) that differs from the menu.
    //
    // An override table rather than columns on the product: a restaurant with
    // one price for everything writes no rows at all, and the common case stays
    // exactly as cheap to read as it was. Columns would have put four nullable
    // prices on every product to serve the minority that use them.
    '''
    CREATE TABLE IF NOT EXISTS pos_product_prices (
      id          bigserial PRIMARY KEY,
      product_id  bigint    NOT NULL REFERENCES pos_products(id) ON DELETE CASCADE,
      branch_id   bigint    REFERENCES pos_branches(id) ON DELETE CASCADE,
      -- NULL means "every order type at this branch". A row naming one applies
      -- only to it, and beats the branch-wide row — same most-specific-wins
      -- rule the settings table follows.
      order_type  text,
      price_minor bigint,
      -- Sold here at all. A branch that has run out for the season sets false
      -- rather than deleting a product other branches still sell.
      is_available boolean  NOT NULL DEFAULT true,
      CONSTRAINT pos_product_prices_price_sane
        CHECK (price_minor IS NULL OR price_minor >= 0),
      CONSTRAINT pos_product_prices_order_type_known CHECK (
        order_type IS NULL
        OR order_type IN ('dine_in', 'takeaway', 'delivery', 'drive_thru')),
      -- A row that overrides nothing is a row somebody will wonder about.
      CONSTRAINT pos_product_prices_says_something
        CHECK (price_minor IS NOT NULL OR NOT is_available)
    )
    ''',
    // NULLs are distinct in a UNIQUE constraint, so the branch-wide and
    // order-type-wide rows need their own partial indexes to be unique at all.
    // Without these a product could carry two different delivery prices and
    // nothing would say which was meant.
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_product_prices_specific
      ON pos_product_prices (product_id, branch_id, order_type)
      WHERE branch_id IS NOT NULL AND order_type IS NOT NULL
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_product_prices_branch_wide
      ON pos_product_prices (product_id, branch_id)
      WHERE branch_id IS NOT NULL AND order_type IS NULL
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS pos_product_prices_channel_wide
      ON pos_product_prices (product_id, order_type)
      WHERE branch_id IS NULL AND order_type IS NOT NULL
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_product_prices_lookup_idx
      ON pos_product_prices (branch_id, product_id)
    ''',

    // Modifier economics, on the group.
    //
    // `free_options` is the one worth naming: "two toppings included, then 5.00
    // each" is how half the market prices a pizza, and the schema could express
    // neither half of that sentence.
    '''
    ALTER TABLE pos_modifier_groups
      ADD COLUMN IF NOT EXISTS min_select integer NOT NULL DEFAULT 0
    ''',
    '''
    ALTER TABLE pos_modifier_groups
      ADD COLUMN IF NOT EXISTS free_options integer NOT NULL DEFAULT 0
    ''',
    '''
    DO \$\$ BEGIN
      ALTER TABLE pos_modifier_groups ADD CONSTRAINT pos_modifier_groups_selection_sane
        CHECK (min_select >= 0 AND free_options >= 0 AND min_select <= max_select);
    EXCEPTION WHEN duplicate_object THEN NULL; END \$\$
    ''',
    // A required group is one that needs at least one. Stated once here so the
    // two ways of saying it cannot drift apart.
    '''
    UPDATE pos_modifier_groups SET min_select = 1
     WHERE is_required AND min_select = 0
    ''',

    // Pre-selected when the sheet opens. "Regular size" already ticked is the
    // difference between three taps and one.
    '''
    ALTER TABLE pos_modifiers
      ADD COLUMN IF NOT EXISTS is_default boolean NOT NULL DEFAULT false
    ''',
  ]),
  // Combos — a meal at one price.
  //
  // Ubiquitous in Egyptian QSR and unpriceable until now: the schema could
  // describe a sandwich, chips and a drink as three lines at three prices, and
  // had no way to say the three together cost 85.00.
  //
  // A combo is **not** a product with modifiers. Its components are real menu
  // items that a kitchen has to make and a receipt has to list, where a modifier
  // is an adjustment to one item. Flattening them into modifiers would price
  // correctly and hand the kitchen a docket for a sandwich with "chips" written
  // on the side of it.
  PosMigration(18, 'combos — a meal at one price', [
    '''
    CREATE TABLE IF NOT EXISTS pos_combos (
      id            bigserial PRIMARY KEY,
      restaurant_id bigint    NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      -- One category, like a product: it has to appear somewhere on the grid.
      category_id   bigint    NOT NULL REFERENCES pos_categories(id) ON DELETE RESTRICT,
      name_en       text      NOT NULL,
      name_ar       text,
      -- What the meal costs. Not derived from the components — the whole point
      -- is that it is less than their sum.
      price_minor   bigint    NOT NULL,
      tax_group_id  bigint    REFERENCES pos_tax_groups(id) ON DELETE SET NULL,
      sku           text,
      is_available  boolean   NOT NULL DEFAULT true,
      sort_order    integer   NOT NULL DEFAULT 0,
      CONSTRAINT pos_combos_price_sane CHECK (price_minor >= 0),
      CONSTRAINT pos_combos_sku_unique UNIQUE (restaurant_id, sku)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_combos_category_idx
      ON pos_combos (category_id)
    ''',

    // "Choose a sandwich", "choose a drink". A group with one option and a
    // minimum of one is a fixed component nobody is asked about.
    '''
    CREATE TABLE IF NOT EXISTS pos_combo_groups (
      id         bigserial PRIMARY KEY,
      combo_id   bigint    NOT NULL REFERENCES pos_combos(id) ON DELETE CASCADE,
      name_en    text      NOT NULL,
      name_ar    text,
      min_select integer   NOT NULL DEFAULT 1,
      max_select integer   NOT NULL DEFAULT 1,
      sort_order integer   NOT NULL DEFAULT 0,
      CONSTRAINT pos_combo_groups_selection_sane
        CHECK (min_select >= 0 AND max_select >= 1 AND min_select <= max_select)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_combo_groups_combo_idx
      ON pos_combo_groups (combo_id)
    ''',

    // Each option is a real menu item. `price_delta_minor` is the upgrade —
    // large chips instead of regular, +5.00 — and is usually zero.
    '''
    CREATE TABLE IF NOT EXISTS pos_combo_options (
      id                bigserial PRIMARY KEY,
      combo_group_id    bigint    NOT NULL REFERENCES pos_combo_groups(id) ON DELETE CASCADE,
      -- RESTRICT, not CASCADE: deleting a product must not silently empty a
      -- combo group and leave a meal nobody can complete.
      product_id        bigint    NOT NULL REFERENCES pos_products(id) ON DELETE RESTRICT,
      price_delta_minor bigint    NOT NULL DEFAULT 0,
      sort_order        integer   NOT NULL DEFAULT 0,
      CONSTRAINT pos_combo_options_once UNIQUE (combo_group_id, product_id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_combo_options_group_idx
      ON pos_combo_options (combo_group_id)
    ''',

    // What a combo line was actually made of.
    //
    // The order line carries the combo's name and the combo's price; this
    // carries the items, so the kitchen knows what to make and a receipt can
    // list them under it. Snapshotted names, for the same reason a line's is.
    '''
    CREATE TABLE IF NOT EXISTS pos_order_line_items (
      id            bigserial PRIMARY KEY,
      order_line_id bigint    NOT NULL REFERENCES pos_order_lines(id) ON DELETE CASCADE,
      menu_item_id  bigint,
      name_snapshot text      NOT NULL,
      quantity      integer   NOT NULL DEFAULT 1,
      sort_order    integer   NOT NULL DEFAULT 0,
      CONSTRAINT pos_order_line_items_quantity_positive CHECK (quantity > 0)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS pos_order_line_items_line_idx
      ON pos_order_line_items (order_line_id)
    ''',

    // A combo line names its combo. Nullable, because every line written until
    // now is not one.
    '''
    ALTER TABLE pos_order_lines ADD COLUMN IF NOT EXISTS combo_id bigint
      REFERENCES pos_combos(id) ON DELETE SET NULL
    ''',
  ]),
  PosMigration(19, 'who the receipt says sold the food', [
    // One row per branch. Not per restaurant: ETA's seller block carries a
    // branch code and a branch address, and a restaurant group filing one
    // address for four branches is filing three wrong ones.
    //
    // Every text column is NOT NULL DEFAULT '' rather than nullable. A profile
    // is filled in over several sittings — somebody types the name today and
    // finds the activity code next week — so "not yet entered" is the normal
    // state of half these columns, and a NULL that means the same thing as ''
    // only buys two ways to spell it and a coalesce at every read.
    '''
    CREATE TABLE IF NOT EXISTS pos_receipt_profiles (
      id                  bigserial   PRIMARY KEY,
      restaurant_id       bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id           bigint      NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      trade_name          text        NOT NULL DEFAULT '',
      -- ETA's `rin`. Nine digits, but unconstrained here: the shape is checked
      -- in Dart where the message can name the box, and a CHECK would also
      -- forbid saving a half-typed profile, which is the normal way one is
      -- entered.
      registration_number text        NOT NULL DEFAULT '',
      activity_code       text        NOT NULL DEFAULT '',
      -- Deliberately not pos_branches.code: that one is the invoice prefix and
      -- the restaurant chooses it. This one the tax authority chose.
      branch_code         text        NOT NULL DEFAULT '',
      country             text        NOT NULL DEFAULT 'EG',
      governate           text        NOT NULL DEFAULT '',
      region_city         text        NOT NULL DEFAULT '',
      street              text        NOT NULL DEFAULT '',
      building_number     text        NOT NULL DEFAULT '',
      postal_code         text        NOT NULL DEFAULT '',
      floor               text        NOT NULL DEFAULT '',
      room                text        NOT NULL DEFAULT '',
      landmark            text        NOT NULL DEFAULT '',
      additional_info     text        NOT NULL DEFAULT '',
      phone               text        NOT NULL DEFAULT '',
      header_note         text        NOT NULL DEFAULT '',
      footer_note         text        NOT NULL DEFAULT '',
      -- Two managers, an office and a counter. Checked on write.
      revision            integer     NOT NULL DEFAULT 0,
      updated_at          timestamptz NOT NULL DEFAULT now(),
      updated_by          bigint      REFERENCES pos_staff(id) ON DELETE SET NULL,
      CONSTRAINT pos_receipt_profiles_branch_unique UNIQUE (branch_id)
    )
    ''',
  ]),
  PosMigration(20, 'the e-receipt queue Egypt requires', [
    // A second destination beside the platform outbox, not a reuse of it.
    //
    // They look alike and are not: the outbox carries whatever the platform
    // wants in whatever order, and a failed row can be retried forever. This
    // one carries documents in a **chain** — each receipt names the uuid of the
    // one before it from the same device — and has a legal deadline attached.
    // Folding them together would mean one drain deciding retry policy for
    // both, and the wrong answer for this one is a receipt filed late.
    '''
    CREATE TABLE IF NOT EXISTS pos_eta_receipts (
      id              bigserial   PRIMARY KEY,
      restaurant_id   bigint      NOT NULL REFERENCES pos_restaurants(id) ON DELETE CASCADE,
      branch_id       bigint      NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      -- The sale this documents. Not a foreign key onto a refund: a refund is
      -- its own receipt with its own row and its own uuid.
      order_id        bigint      NOT NULL REFERENCES pos_orders(id) ON DELETE RESTRICT,
      refund_id       bigint      REFERENCES pos_refunds(id) ON DELETE RESTRICT,
      -- Which till issued it. The chain is per device, so this is not
      -- decoration: two tills in one branch have two independent chains.
      device_serial   text        NOT NULL,
      -- SHA-256 of the canonical document, 64 lowercase hex. Computed on this
      -- machine before anything is sent, which is what makes a resubmission
      -- recognisable as the same document rather than as a second one.
      uuid            text        NOT NULL,
      previous_uuid   text        NOT NULL DEFAULT '',
      receipt_number  text        NOT NULL,
      receipt_type    text        NOT NULL,
      -- The document exactly as it will be sent, and the canonical text it was
      -- hashed from. Both stored: a rejection two days later is investigated
      -- against what was actually submitted, not against what rebuilding it
      -- today would produce from a menu that has since changed.
      document        jsonb       NOT NULL,
      canonical       text        NOT NULL,
      signature       text,
      issued_at       timestamptz NOT NULL,
      status          text        NOT NULL DEFAULT 'pending',
      attempts        integer     NOT NULL DEFAULT 0,
      last_attempt_at timestamptz,
      -- Set the moment the authority accepts it. The gap between issued_at and
      -- this is the number the 24-hour rule is about.
      submitted_at    timestamptz,
      -- What came back: their submission id, their long id, and the reason if
      -- they refused.
      submission_uuid text,
      long_id         text,
      error_message   text,
      created_at      timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_eta_receipts_status_known CHECK (
        status IN ('pending', 'signed', 'submitted', 'accepted', 'rejected', 'cancelled')
      ),
      -- The uuid is a fingerprint of the document, so a duplicate is the same
      -- document twice and never two sales. Unique per branch rather than
      -- globally: two branches are two taxpayer submissions.
      CONSTRAINT pos_eta_receipts_uuid_unique UNIQUE (branch_id, uuid)
    )
    ''',
    // The drain's query: the oldest thing not yet accepted, per device, in the
    // order it was issued. Partial, because an accepted receipt is history and
    // the queue is only ever read for what is outstanding.
    '''
    CREATE INDEX IF NOT EXISTS pos_eta_receipts_outstanding_idx
      ON pos_eta_receipts (branch_id, device_serial, issued_at)
      WHERE status <> 'accepted'
    ''',
    // "Has this order been filed" — asked when a receipt is reprinted and by
    // the screen that shows what has not cleared.
    '''
    CREATE INDEX IF NOT EXISTS pos_eta_receipts_order_idx
      ON pos_eta_receipts (order_id)
    ''',
    // The chain head, per device. Read before every new receipt is built and
    // written after it — under a row lock, because two threads reading the
    // same head would build two receipts claiming the same predecessor and
    // the authority would reject the second.
    '''
    CREATE TABLE IF NOT EXISTS pos_eta_chains (
      id            bigserial   PRIMARY KEY,
      branch_id     bigint      NOT NULL REFERENCES pos_branches(id) ON DELETE CASCADE,
      device_serial text        NOT NULL,
      last_uuid     text        NOT NULL DEFAULT '',
      updated_at    timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT pos_eta_chains_device_unique UNIQUE (branch_id, device_serial)
    )
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
