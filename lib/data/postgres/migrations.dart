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
  Future<List<int>> migrate(DeploymentConfig config) async => _db.runTx(config, (tx) async {
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
