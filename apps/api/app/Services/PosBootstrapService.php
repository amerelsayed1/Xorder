<?php

namespace App\Services;

use App\Enums\RoleEnum;
use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Models\Category;
use App\Models\Charge;
use App\Models\Customer;
use App\Models\DiningTable;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Models\PosLicence;
use App\Models\PosTerminal;
use App\Models\TaxRule;
use App\Models\TenderType;
use App\Models\User;
use App\Support\PosPin;

/**
 * Assembles the bootstrap bundle (POS-BE-023): the till's entire world in one
 * document — one call, one config_version, one thing to invalidate.
 *
 * THE SERIALIZATION KEYS ARE FROZEN (2026-09-02, recorded in
 * BACKEND_TO_POS.md §023). The Flutter bundle parser reads exactly these
 * names; it tolerates extras but a renamed key means an empty till, and a
 * JSON FLOAT in any *_minor field makes the client DROP that product — every
 * price is an int in minor units, converted through the tenant currency's
 * exponent, never assumed to be cents.
 *
 * Callers must have pinned TenantContext to the terminal's restaurant (the
 * pos.device middleware does; the claim path overrides explicitly), so every
 * scoped query below lands on the right tenant. `staff` is the one block
 * scoped BY HAND — User carries no RestaurantScope, and the pin block is the
 * single wire on which a PIN verifier ever travels.
 */
class PosBootstrapService
{
    /**
     * How many customers ride in the bundle. Big enough to hold a busy
     * restaurant's regulars, small enough that the bootstrap stays a download
     * and not an export.
     */
    private const CUSTOMER_LIMIT = 2000;

    public function __construct(private readonly ReceiptProfileService $receiptProfiles) {}

    public function bundle(PosTerminal $terminal): array
    {
        $restaurant = $terminal->restaurant()->with('features')->first();
        $currency = $restaurant->currency;
        $exp = 10 ** $currency->exponent();
        $branches = $restaurant->branches()->where('is_active', true)->get();

        return [
            'config_version' => (int) $restaurant->pos_config_version,
            'synced_at' => now()->toIso8601String(),
            'server_time' => now()->toIso8601String(), // POS-BE-020
            'terminal' => [
                'id' => $terminal->terminal_id,
                'name' => $terminal->name,
                'branch_id' => $terminal->branch_id,
                'deployment_mode' => $terminal->deployment_mode,
                'sync_policy' => $terminal->sync_policy,
            ],
            'restaurant' => [
                'id' => $restaurant->id,
                'name' => $restaurant->name_en ?: ($restaurant->name_ar ?: $restaurant->slug),
                'name_ar' => $restaurant->name_ar,
                'slug' => $restaurant->slug,
                'tax_registration_number' => $restaurant->tax_registration_number,
                // Mandatory (A7): hardcoding an exponent of 2 is a bug for a
                // Kuwaiti tenant, and one the client cannot detect on its own.
                'currency' => $currency->value,
                'exponent' => $currency->exponent(),
                'timezone' => $restaurant->localTimezone(),
                'default_language' => $restaurant->default_language->value,
            ],
            'branches' => $branches
                ->map(fn ($b) => [
                    'id' => $b->id,
                    'code' => $b->code,
                    'name' => $b->name_en ?: $b->name_ar,
                    'supported_order_types' => $b->supported_order_types ?? [],
                ])->values()->all(),
            // A3 (new key, 2026-09-22): who the receipt says sold the food, one
            // row per active branch — including branches nobody has authored
            // yet, projected from the restaurant, because a till that gets no
            // row for its branch prints compiled-in defaults, which is the
            // whole bug. Names are the till's `pos_receipt_profiles` columns.
            'receipt_profiles' => $this->receiptProfiles->wire($restaurant, $branches),
            // 2026-09-02 amendment: the branch floor, so a cloud till can seat
            // dine-in tickets. Scoped to the TERMINAL'S branch (decision
            // recorded in BACKEND_TO_POS.md §023). No occupancy state — the
            // cloud till tracks its own seating locally.
            'tables' => DiningTable::query()
                ->where('branch_id', $terminal->branch_id)
                ->where('is_active', true)
                ->with('diningArea')
                ->orderBy('label')
                ->get()
                ->map(fn ($t) => [
                    'id' => $t->id,
                    'branch_id' => $t->branch_id,
                    'label' => $t->label,
                    'seats' => $t->seats_count,
                    'area_name' => $t->diningArea?->name_en ?: $t->diningArea?->name_ar,
                    'is_active' => (bool) $t->is_active,
                ])->values()->all(),
            'catalog' => $this->catalog($exp),
            'money' => [
                'tax_rules' => TaxRule::orderBy('sort_order')->orderBy('id')->get()
                    ->map(fn ($r) => [
                        'id' => $r->id, 'name' => $r->name, 'rate_bp' => $r->rate_bp,
                        'mode' => $r->mode, 'applies_to' => $this->scopeBlock($r->applies_to),
                        'sort_order' => $r->sort_order,
                    ])->values()->all(),
                'charges' => Charge::orderBy('sort_order')->orderBy('id')->get()
                    ->map(fn ($c) => [
                        'id' => $c->id, 'name' => $c->name, 'kind' => $c->kind,
                        'rate_bp' => $c->rate_bp, 'amount_minor' => $c->amount_minor,
                        'taxable' => $c->taxable, 'applies_to' => $this->scopeBlock($c->applies_to),
                    ])->values()->all(),
                'tender_types' => TenderType::orderBy('sort_order')->orderBy('id')->get()
                    ->map(fn ($t) => [
                        'id' => $t->id, 'name' => $t->name, 'kind' => $t->kind,
                        'is_active' => $t->is_active, 'sort_order' => $t->sort_order,
                    ])->values()->all(),
            ],
            'invoice' => $this->invoiceConfig($restaurant),
            'endpoints' => [
                'base_url' => rtrim((string) config('app.url'), '/'),
                'verify_tls' => true,
                // DIS-1: the database block lives HERE, behind the device
                // credential — never on the unauthenticated setup path. Null
                // for cloud (no branch box).
                'database_host' => null,
                'database_name' => null,
                'database_user' => null,
                'database_port' => null,
            ],
            'pos' => [
                'sync_policy' => $terminal->sync_policy,
                'rounding' => 'none',
                'lock_after_seconds' => null,
                'shift_required' => true,
            ],
            // Never emitted empty — the client reads [] as "everything" only
            // because the alternative is a till that will not configure.
            'modules' => ['pos'],
            'printers' => [],
            'branding' => [
                'display_name' => $restaurant->name_en ?: ($restaurant->name_ar ?: $restaurant->slug),
                'logo_url' => $restaurant->logo_url,
                'accent_hex' => $restaurant->brand_color,
            ],
            'staff' => $this->staff($restaurant->id),
            'customers' => $this->customers($restaurant->id),
            'licence' => PosLicence::query()
                ->where('restaurant_id', $restaurant->id)
                ->live()
                ->latest('id')
                ->first()?->file(),
        ];
    }

    /**
     * The frozen catalog shape: items carry integer price_minor +
     * discounted_price_minor and the COMPLETE resolved option_group_ids
     * (inline + shared + apply_scope auto groups — POS-BE-003 semantics);
     * the groups themselves land once, deduplicated, in option_groups.data
     * with per-option integer price_delta_minor.
     *
     * The per-collection `complete` flags are POS-BE-012 decision (b): they
     * say whether DELTA syncs can report deletions — items and categories
     * soft-delete (true), option groups have no tombstones yet (false,
     * BE-A03), so the client full-pulls that one collection on refresh.
     */
    private function catalog(int $exp): array
    {
        $autoGroups = OptionGroup::autoApplied()
            ->with(['options', 'categories:id'])
            ->orderBy('name_en')->orderBy('name_ar')->orderBy('id')
            ->get();

        $items = MenuItem::query()
            ->with(['optionGroups.options', 'sharedOptionGroups.options'])
            ->orderBy('category_id')->orderBy('display_order')->orderBy('id')
            ->get()
            ->each(fn (MenuItem $item) => $item->withAutoOptionGroups($autoGroups));

        $groupIndex = [];
        $itemRows = [];

        foreach ($items as $item) {
            $groups = $item->orderedOptionGroups();

            foreach ($groups as $group) {
                $groupIndex[$group->id] ??= [
                    'id' => $group->id,
                    'name_en' => $group->name_en,
                    'name_ar' => $group->name_ar,
                    'is_required' => (bool) $group->is_required,
                    'max_select' => (int) $group->max_select,
                    'is_variant' => (bool) $group->is_variant,
                    'sort_order' => (int) $group->sort_order,
                    'options' => $group->options->map(fn ($o) => [
                        'id' => $o->id,
                        'name_en' => $o->name_en,
                        'name_ar' => $o->name_ar,
                        // For a variant option this is the REPLACEMENT price;
                        // for an add-on it is the delta. The client keys off
                        // the group's is_variant, same as the menu SPA.
                        'price_delta_minor' => $this->toMinor($o->discounted_price ?? $o->price, $exp),
                        'is_available' => (bool) $o->is_available,
                        'sort_order' => (int) $o->sort_order,
                    ])->values()->all(),
                ];
            }

            [$price, $discounted] = $item->displayPricing();

            $itemRows[] = [
                'id' => $item->id,
                'category_id' => $item->category_id,
                'name_en' => $item->name_en,
                'name_ar' => $item->name_ar,
                'price_minor' => $this->toMinor($price, $exp),
                'discounted_price_minor' => $discounted !== null ? $this->toMinor($discounted, $exp) : null,
                'sku' => null,      // POS-BE-004 deferred from this wave
                'barcode' => null,  // POS-BE-004 deferred from this wave
                'is_available' => (bool) $item->is_available,
                'sort_order' => (int) $item->display_order,
                'option_group_ids' => $groups->pluck('id')->values()->all(),
            ];
        }

        $categories = Category::query()
            ->orderBy('display_order')->orderBy('id')
            ->get()
            ->map(fn ($c) => [
                'id' => $c->id,
                'name_en' => $c->name_en,
                'name_ar' => $c->name_ar,
                'slug' => null,
                'sort_order' => (int) $c->display_order,
                'is_active' => (bool) $c->is_active,
            ])->values()->all();

        return [
            'categories' => ['data' => $categories, 'deleted_ids' => [], 'complete' => true],
            'items' => ['data' => $itemRows, 'deleted_ids' => [], 'complete' => true],
            'option_groups' => [
                'data' => array_values($groupIndex),
                'deleted_ids' => [],
                'complete' => false,
            ],
        ];
    }

    /** @return array<int,array<string,mixed>> */
    /**
     * The customer directory, so a cashier can find a regular with no internet.
     *
     * **Sent down rather than searched over the wire (owner decision, 27 Sep
     * 2026).** A till is offline-first and the counter is exactly where the
     * connection is worst; a search box that needs the platform is a search
     * box that fails during a power cut, which is when the queue is longest.
     *
     * **Capped, and newest first.** A directory is unbounded — a restaurant
     * that has traded for years has tens of thousands of numbers, and putting
     * all of them in every bundle would make the bootstrap the biggest thing
     * the till ever downloads, on every config change. The cap takes the most
     * recently seen, which is the half of the directory a counter actually
     * asks for; anyone older is still reachable by creating them again, which
     * `CustomerDirectory::upsert()` resolves back to the same person by phone.
     *
     * Addresses: the default one only. A till prints one address on a delivery
     * docket and has nowhere to show a chooser.
     */
    private function customers(int $restaurantId): array
    {
        return Customer::query()
            ->where('restaurant_id', $restaurantId)
            ->with(['addresses' => fn ($q) => $q->orderByDesc('is_default')->limit(1)])
            ->orderByDesc('updated_at')
            ->limit(self::CUSTOMER_LIMIT)
            ->get()
            ->map(fn (Customer $c) => [
                'id' => $c->id,
                'name' => $c->name,
                'phone' => $c->phone,
                'email' => $c->email,
                'address' => $c->addresses->first()?->address,
            ])
            ->all();
    }

    private function staff(int $restaurantId): array
    {
        // User has no RestaurantScope — scoped by hand, the StaffController
        // pattern. Active tenant accounts only; a cashier with no PIN gets
        // null and simply cannot sign in offline.
        return User::query()
            ->where('restaurant_id', $restaurantId)
            ->whereIn('role', [RoleEnum::RESTAURANT_ADMIN, RoleEnum::RESTAURANT_STAFF])
            ->where('status', UserStatus::ACTIVE)
            ->with('tenantRole')
            ->orderBy('id')
            ->get()
            ->map(fn (User $u) => [
                'id' => $u->id,
                'name' => $u->name,
                'username' => $u->username,
                'role_id' => $u->role_id,
                // CB-09 D8: purchase.manage is the platform's capability AND
                // the till's own canonical name, so sending it would light up
                // the till-local Purchasing pane for exactly the people the
                // platform made buyers: two authors of one row. On a cloud
                // terminal the platform is the only author of purchasing, and
                // no till screen should check this key, so it never travels.
                'capabilities' => array_values(array_diff(
                    $u->tenantCapabilities(),
                    [TenantCapability::PURCHASE_MANAGE->value],
                )),
                'is_active' => true,
                'pin' => PosPin::wire($u->pos_pin_salt, $u->pos_pin_hash),
            ])->values()->all();
    }

    /** @return array<string,list<int|string>> */
    private function scopeBlock(?array $appliesTo): array
    {
        return [
            'order_types' => array_values($appliesTo['order_types'] ?? []),
            'branch_ids' => array_values($appliesTo['branch_ids'] ?? []),
            'category_ids' => array_values($appliesTo['category_ids'] ?? []),
            'item_ids' => array_values($appliesTo['item_ids'] ?? []),
        ];
    }

    /** POS-BE-008 sequence settings, read-only here. */
    public function invoiceConfig($restaurant): array
    {
        $config = $restaurant->pos_invoice_config ?? [];

        return [
            'prefix_source' => $config['prefix_source'] ?? 'branch_code',
            'padding' => (int) ($config['padding'] ?? 6),
            'reset' => $config['reset'] ?? 'yearly',
        ];
    }

    /** decimal(10,2) string → integer minor units. Ints only on this wire. */
    private function toMinor(mixed $decimal, int $exp): int
    {
        return (int) round(((float) $decimal) * $exp);
    }
}
