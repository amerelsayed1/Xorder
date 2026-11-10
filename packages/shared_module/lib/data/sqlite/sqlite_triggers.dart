/// The PostgreSQL triggers a cloud till relies on, written for SQLite
/// (pos-cloud-single-till-sqlite, stage 4).
///
/// Translated by hand from each function's current definition (PostgreSQL
/// migration 64), with the same refusals in the same words, because a
/// repository or a screen may show them. What SQLite cannot do the same way:
///
/// * **A BEFORE trigger cannot change the row being written.** The business-day
///   stamp therefore runs AFTER INSERT and updates the row it just wrote.
/// * **No deferred triggers.** `pos_refunds_tendered_in_full` is checked by the
///   refunds repository before commit instead (`PostgresRefundsRepository`).
/// * **No TRUNCATE.** Its guards have nothing to guard.
///
/// Not here, because a cloud till never writes those tables: purchase orders,
/// supplier invoices and supplier payments.
///
/// Also here: the PostgreSQL CHECKs SQLite cannot express as a CHECK — the
/// ones with a regular expression or an array test (`_shapeChecks`), kept as
/// triggers with the same rule, `GLOB` standing in for the expression.
final sqliteTriggers = <String>[
  for (final (table, name, ok) in _shapeChecks)
    for (final op in ['INSERT', 'UPDATE'])
      '''
CREATE TRIGGER ${name}_${op.toLowerCase()} BEFORE $op ON $table
  WHEN NOT ($ok)
BEGIN
  SELECT RAISE(ABORT, 'new row for relation "$table" violates check constraint "$name"');
END''',

  // Audit and backups are append-only.
  for (final (table, extra) in [
    ('pos_audit_events', ''),
    (
      'pos_backups',
      ' — a backup that failed is the record that it failed. Fix what it '
          'reports and take another one; the new row is what makes the warning '
          'go away.',
    ),
  ])
    for (final op in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER ${table}_no_${op.toLowerCase()} BEFORE $op ON $table
BEGIN
  SELECT RAISE(ABORT, '$table is append-only; $op is not permitted$extra');
END''',

  // A new business gets the standard units.
  '''
CREATE TRIGGER pos_businesses_seed_units AFTER INSERT ON pos_businesses
BEGIN
  INSERT INTO pos_units (business_id, code, name_en, name_ar,
                         eta_unit_type, allows_fraction, sort_order)
  VALUES (NEW.id, 'ea',   'Each',       'قطعة',     'EA',  0, 10),
         (NEW.id, 'kg',   'Kilogram',   'كيلوجرام', 'KGM', 1, 20),
         (NEW.id, 'g',    'Gram',       'جرام',     'GRM', 1, 30),
         (NEW.id, 'l',    'Litre',      'لتر',      'LTR', 1, 40),
         (NEW.id, 'ml',   'Millilitre', 'مليلتر',   'MLT', 1, 50),
         (NEW.id, 'box',  'Box',        'علبة',     'BX',  0, 60),
         (NEW.id, 'pack', 'Pack',       'عبوة',     'PK',  0, 70)
  ON CONFLICT (business_id, code) DO NOTHING;
END''',

  // An option group reaches its items one way at a time.
  for (final op in ['INSERT', 'UPDATE'])
    '''
CREATE TRIGGER pos_product_modifier_groups_follow_scope_${op.toLowerCase()}
  BEFORE $op ON pos_product_modifier_groups
  WHEN (SELECT apply_scope FROM pos_modifier_groups WHERE id = NEW.group_id)
       <> 'items'
BEGIN
  SELECT RAISE(ABORT, 'option group "' || g.name_en || '" already reaches ' ||
      CASE g.apply_scope WHEN 'all' THEN 'every item'
                         ELSE 'the items in its categories' END ||
      ' by itself, so it cannot also be linked to one item — set it back to ' ||
      'chosen items first, or leave the item to pick it up')
    FROM pos_modifier_groups AS g WHERE g.id = NEW.group_id;
END''',
  for (final op in ['INSERT', 'UPDATE'])
    '''
CREATE TRIGGER pos_modifier_group_categories_follow_scope_${op.toLowerCase()}
  BEFORE $op ON pos_modifier_group_categories
  WHEN (SELECT apply_scope FROM pos_modifier_groups WHERE id = NEW.group_id)
       <> 'categories'
BEGIN
  SELECT RAISE(ABORT, 'option group "' || g.name_en || '" applies to ' ||
      CASE g.apply_scope WHEN 'all' THEN 'every item'
                         ELSE 'chosen items' END ||
      ', not to chosen categories — set it to categories before linking one')
    FROM pos_modifier_groups AS g WHERE g.id = NEW.group_id;
END''',
  '''
CREATE TRIGGER pos_modifier_groups_scope_leaves_no_links
  BEFORE UPDATE OF apply_scope ON pos_modifier_groups
  WHEN OLD.apply_scope IS NOT NEW.apply_scope
BEGIN
  SELECT RAISE(ABORT, 'option group "' || NEW.name_en ||
      '" is still linked to items one by one, so it cannot start applying to '
      || NEW.apply_scope || ' — remove those links first; a group reaches its ' ||
      'items through one path at a time')
   WHERE NEW.apply_scope <> 'items' AND EXISTS (
     SELECT 1 FROM pos_product_modifier_groups WHERE group_id = NEW.id);
  SELECT RAISE(ABORT, 'option group "' || NEW.name_en ||
      '" is still linked to categories, so it cannot start applying to ' ||
      NEW.apply_scope || ' — remove those links first; a group reaches its ' ||
      'items through one path at a time')
   WHERE NEW.apply_scope <> 'categories' AND EXISTS (
     SELECT 1 FROM pos_modifier_group_categories WHERE group_id = NEW.id);
END''',

  // A sale, a refund and a shift are filed under the business day that was
  // open when they happened, unless the writer named one.
  for (final (table, at) in [
    ('pos_orders', 'occurred_at'),
    ('pos_refunds', 'occurred_at'),
    ('pos_shifts', 'opened_at'),
  ])
    '''
CREATE TRIGGER ${table}_business_day AFTER INSERT ON $table
  WHEN NEW.business_day_id IS NULL
BEGIN
  UPDATE $table SET business_day_id = (
    SELECT d.id FROM pos_business_days AS d
     WHERE d.branch_id = NEW.branch_id
       AND d.opened_at <= coalesce(NEW.$at, now())
       AND (d.closed_at IS NULL OR coalesce(NEW.$at, now()) < d.closed_at)
     ORDER BY d.opened_at DESC
     LIMIT 1)
   WHERE rowid = NEW.rowid;
END''',

  // A receipt on paper is not queued again. (The writer stamps printed_at; a
  // CHECK refuses 'printed' without it.)
  '''
CREATE TRIGGER pos_print_jobs_print_once BEFORE UPDATE ON pos_print_jobs
  WHEN OLD.status = 'printed'
BEGIN
  SELECT RAISE(ABORT, 'print job ' || OLD.id || ' already printed at ' ||
      OLD.printed_at || ' — a receipt that has been on paper cannot be queued ' ||
      'again; issue a reprint, which is a new job and is recorded against ' ||
      'whoever asked for it');
END''',

  // Nothing converts one unit into another.
  '''
CREATE TRIGGER pos_products_unit_follows_stock BEFORE UPDATE ON pos_products
  WHEN coalesce(nullif(trim(OLD.stock_unit), ''), 'ea')
       IS NOT coalesce(nullif(trim(NEW.stock_unit), ''), 'ea')
BEGIN
  SELECT RAISE(ABORT, NEW.name_en || ' has ' ||
      printf('%.3f', held.quantity_milli / 1000.0) || ' ' || held.unit ||
      ' in stock at branch ' || held.branch_id || ', so its unit cannot change ' ||
      'to ' || coalesce(nullif(trim(NEW.stock_unit), ''), 'ea') ||
      ' — nothing converts one unit into another; it can change once none is ' ||
      'held in ' || held.unit)
    FROM (SELECT * FROM pos_stock_levels
           WHERE product_id = NEW.id AND quantity_milli <> 0
             AND unit <> coalesce(nullif(trim(NEW.stock_unit), ''), 'ea')
           ORDER BY branch_id LIMIT 1) AS held;
END''',
  '''
CREATE TRIGGER pos_stock_levels_keep_unit BEFORE UPDATE ON pos_stock_levels
  WHEN OLD.unit IS NOT NEW.unit AND OLD.quantity_milli <> 0
BEGIN
  SELECT RAISE(ABORT, coalesce(
      (SELECT name_en FROM pos_products WHERE id = OLD.product_id),
      'product ' || OLD.product_id) || ' is held in stock as ' ||
      printf('%.3f', OLD.quantity_milli / 1000.0) || ' ' || OLD.unit ||
      ' at branch ' || OLD.branch_id || ', so it cannot be counted in ' ||
      NEW.unit || ' — nothing converts one unit into another; book it in as ' ||
      OLD.unit || ', or wait until none is held');
END''',

  // A refund moves its order's counters and status, and only from money that
  // arrived.
  '''
CREATE TRIGGER pos_refunds_apply AFTER INSERT ON pos_refunds
BEGIN
  SELECT RAISE(ABORT,
      'a refund must belong to the same branch as the order it refunds')
    FROM pos_orders AS o
   WHERE o.id = NEW.order_id
     AND (o.business_id <> NEW.business_id OR o.branch_id <> NEW.branch_id);
  SELECT RAISE(ABORT, 'order ' || o.id || ' is ' || o.status ||
      ', so there is nothing to refund')
    FROM pos_orders AS o
   WHERE o.id = NEW.order_id
     AND o.status NOT IN ('PAID', 'CLOSED', 'PARTIALLY_REFUNDED');
  UPDATE pos_orders
     SET refunded_minor = refunded_minor + NEW.total_minor,
         status = CASE
           WHEN refunded_minor + NEW.total_minor >= total_minor
             THEN 'REFUNDED' ELSE 'PARTIALLY_REFUNDED' END,
         status_changed_at = NEW.occurred_at
   WHERE id = NEW.order_id;
END''',
  '''
CREATE TRIGGER pos_refund_lines_apply AFTER INSERT ON pos_refund_lines
BEGIN
  SELECT RAISE(ABORT, 'refund line ' || NEW.order_line_id ||
      ' does not belong to the order being refunded')
   WHERE NOT EXISTS (
     SELECT 1 FROM pos_order_lines
      WHERE id = NEW.order_line_id
        AND order_id = (SELECT order_id FROM pos_refunds
                         WHERE id = NEW.refund_id));
  UPDATE pos_order_lines
     SET refunded_quantity = refunded_quantity + NEW.quantity
   WHERE id = NEW.order_line_id
     AND order_id = (SELECT order_id FROM pos_refunds WHERE id = NEW.refund_id);
END''',

  // The owner: one per business, holding every permission, with no extras.
  for (final op in ['INSERT', 'UPDATE'])
    '''
CREATE TRIGGER pos_user_overrides_no_owner_${op.toLowerCase()}
  BEFORE $op ON pos_user_permission_overrides
BEGIN
  SELECT RAISE(ABORT, s.name || ' is the owner — a permission exception on ' ||
      'the owner means nothing if it allows and locks the restaurant out if ' ||
      'it denies, so there is nothing to set here')
    FROM pos_users AS s JOIN pos_roles AS r ON r.id = s.role_id
   WHERE s.id = NEW.user_id AND r.code = 'owner';
END''',
  for (final op in ['INSERT', 'UPDATE'])
    '''
CREATE TRIGGER pos_user_roles_no_owner_${op.toLowerCase()}
  BEFORE $op ON pos_user_roles
BEGIN
  SELECT RAISE(ABORT, 'the owner role cannot be an extra role — to make ' ||
      'somebody the owner, set it as their role (pos_users.role_id), after ' ||
      'disabling the current owner')
   WHERE EXISTS (SELECT 1 FROM pos_roles
                  WHERE id = NEW.role_id AND code = 'owner');
  SELECT RAISE(ABORT, s.name || ' is the owner and already holds every ' ||
      'permission, so the owner is given no extra roles')
    FROM pos_users AS s JOIN pos_roles AS r ON r.id = s.role_id
   WHERE s.id = NEW.user_id AND r.code = 'owner';
END''',
  '''
CREATE TRIGGER pos_users_one_owner_insert BEFORE INSERT ON pos_users
  WHEN NEW.role_id IS NOT NULL AND NEW.is_active
   AND EXISTS (SELECT 1 FROM pos_roles WHERE id = NEW.role_id AND code = 'owner')
BEGIN
  SELECT RAISE(ABORT, incumbent.name || ' is already the owner of this ' ||
      'restaurant, and a restaurant has one — disable ' || incumbent.name ||
      ' first, then appoint the new owner')
    FROM (SELECT name FROM pos_users
           WHERE business_id = NEW.business_id AND role_id = NEW.role_id
             AND is_active AND NOT coalesce(username = NEW.username, 0)
           ORDER BY id LIMIT 1) AS incumbent;
END''',
  '''
CREATE TRIGGER pos_users_one_owner_update BEFORE UPDATE ON pos_users
  WHEN (OLD.role_id IS NOT NEW.role_id OR OLD.is_active IS NOT NEW.is_active)
   AND NEW.role_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM pos_roles WHERE id = NEW.role_id AND code = 'owner')
BEGIN
  SELECT RAISE(ABORT, NEW.name || ' still has extra roles or permission ' ||
      'exceptions — clear them before making them the owner, who holds every ' ||
      'permission already')
   WHERE OLD.role_id IS NOT NEW.role_id
     AND (EXISTS (SELECT 1 FROM pos_user_roles WHERE user_id = NEW.id)
          OR EXISTS (SELECT 1 FROM pos_user_permission_overrides
                      WHERE user_id = NEW.id));
  SELECT RAISE(ABORT, incumbent.name || ' is already the owner of this ' ||
      'restaurant, and a restaurant has one — disable ' || incumbent.name ||
      ' first, then appoint the new owner')
    FROM (SELECT name FROM pos_users
           WHERE business_id = NEW.business_id AND role_id = NEW.role_id
             AND is_active AND id <> NEW.id
           ORDER BY id LIMIT 1) AS incumbent
   WHERE NEW.is_active;
END''',
];

/// (table, constraint, the condition a row must meet) — PostgreSQL's CHECKs
/// that SQLite cannot hold as CHECKs (generator: `CHECK dropped`).
const _shapeChecks = <(String, String, String)>[
  (
    'pos_discounts',
    'pos_discounts_days_are_days',
    // days_of_week <@ ARRAY[1..7]: every element is a day; NULL passes, as
    // the array test is NULL for a NULL array.
    'NEW.days_of_week IS NULL OR NOT EXISTS (SELECT 1 FROM '
        "json_each(NEW.days_of_week) WHERE typeof(value) <> 'integer' "
        'OR value NOT BETWEEN 1 AND 7)',
  ),
  (
    'pos_backups',
    'pos_backups_checksum_shaped',
    // ^[0-9a-f]{64}$
    'NEW.checksum IS NULL OR (length(NEW.checksum) = 64 AND '
        "NEW.checksum NOT GLOB '*[^0-9a-f]*')",
  ),
  (
    'pos_units',
    'pos_units_code_shaped',
    // ^[a-z][a-z0-9_]{0,15}$ (NULL passes, as a NULL test is not false)
    'NEW.code IS NULL OR (length(NEW.code) BETWEEN 1 AND 16 AND '
        "NEW.code GLOB '[a-z]*' AND NEW.code NOT GLOB '*[^a-z0-9_]*')",
  ),
  (
    'pos_units',
    'pos_units_eta_shaped',
    // ^[A-Z0-9]{1,6}$
    'NEW.eta_unit_type IS NULL OR (length(NEW.eta_unit_type) BETWEEN 1 AND 6 '
        "AND NEW.eta_unit_type NOT GLOB '*[^A-Z0-9]*')",
  ),
  (
    'pos_users',
    'pos_users_password_hash_shape',
    // pbkdf2-sha256$<iterations>$<salt>$<key>, base64 salt and key, and at
    // least 600 000 iterations.
    'NEW.password_hash IS NULL OR ('
        "NEW.password_hash GLOB 'pbkdf2-sha256\$[0-9]*\$?*\$?*' AND "
        "substr(NEW.password_hash, 15) NOT GLOB '*[^A-Za-z0-9+/=\$]*' AND "
        "length(substr(NEW.password_hash, 15)) - "
        "length(replace(substr(NEW.password_hash, 15), '\$', '')) = 2 AND "
        "substr(substr(NEW.password_hash, 15), 1, "
        "instr(substr(NEW.password_hash, 15), '\$') - 1) NOT GLOB '*[^0-9]*' AND "
        "CAST(substr(substr(NEW.password_hash, 15), 1, "
        "instr(substr(NEW.password_hash, 15), '\$') - 1) AS INTEGER) >= 600000)",
  ),
];
