<?php

namespace App\Services;

use App\Models\Combo;
use App\Models\MenuItem;
use App\Models\Restaurant;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

/**
 * Prices a diner's order from the menu, never from the phone (XORD-047).
 *
 * The public menu used to post each line's `line_total` and the server added
 * them up, so a modified request could set any price, zero included. Now a
 * line names what was ordered — an item or a combo, and the option ids chosen
 * — and the price, the names and the labels all come from here.
 *
 * **The same menu the diner was shown.** Lines are resolved against
 * {@see PublicMenuService::loadMenu()}, so nothing can be ordered that the menu
 * would not offer: a hidden category, a deleted item, an item from another
 * restaurant, an option that is switched off, a category outside its serving
 * hours. Each of those is a 422 before anything is written.
 *
 * **The same arithmetic the menu does** (`apps/menu/src/composables/useCart.js`
 * `calculateLinePrice`), so a diner is charged what the cart showed:
 *   - item: its discounted price when set, else its price; a size (variant)
 *     option REPLACES that with the size's discounted-else-list price; every
 *     other chosen option ADDS its list price;
 *   - combo: its base price; a variant choice REPLACES it with that choice's
 *     extra price; every other choice ADDS its extra price.
 * Done in minor units, so the sum of lines is exact.
 *
 * Tax, service and discounts are not applied: a diner order carried none
 * before this either, and adding them would change every total a restaurant
 * already quotes. That belongs to the POS pricing work, not to this fix.
 */
class DinerOrderPricing
{
    public function __construct(private readonly PublicMenuService $menu) {}

    /**
     * @param  list<array<string,mixed>>  $lines  validated request lines
     * @return array{items: list<array<string,mixed>>, total: string}
     *
     * @throws ValidationException
     */
    public function price(Restaurant $restaurant, array $lines, string $lang): array
    {
        $loaded = $this->menu->loadMenu($restaurant);

        /** @var Collection<int, MenuItem> $items */
        $items = collect();
        foreach ($loaded['categories'] as $category) {
            $serving = $category->isAvailableNow();
            foreach ($category->menuItems as $item) {
                $item->setAttribute('_serving', $serving);
                $items->put($item->id, $item);
            }
        }
        /** @var Collection<int, Combo> $combos */
        $combos = $loaded['combos']->keyBy('id');

        $priced = [];
        $totalMinor = 0;
        foreach (array_values($lines) as $i => $line) {
            $row = ($line['kind'] ?? 'item') === 'combo'
                ? $this->priceCombo($combos, $line, $lang, $i)
                : $this->priceItem($items, $line, $lang, $i);
            $totalMinor += $row['line_total_minor'];
            $priced[] = $row;
        }

        return [
            'items' => array_map(function (array $row) {
                $row['unit_price'] = self::major($row['unit_price_minor']);
                $row['line_total'] = self::major($row['line_total_minor']);
                unset($row['unit_price_minor'], $row['line_total_minor']);

                return $row;
            }, $priced),
            'total' => self::major($totalMinor),
        ];
    }

    /** @param Collection<int, MenuItem> $items */
    private function priceItem(Collection $items, array $line, string $lang, int $i): array
    {
        $item = $items->get((int) ($line['menu_item_id'] ?? 0));
        if ($item === null || ! $item->is_available || ! $item->getAttribute('_serving')) {
            $this->refuse("items.$i.menu_item_id", 'menu_item_unavailable');
        }

        $chosen = collect($line['option_ids'] ?? [])->map(fn ($id) => (int) $id)->unique()->values();
        $groups = $item->orderedOptionGroups();

        $baseMinor = self::minor($item->discounted_price ?? $item->price);
        $addonsMinor = 0;
        $variant = null;
        $extras = [];
        $matched = collect();

        foreach ($groups as $group) {
            $available = $group->options->where('is_available', true);
            $picked = $available->filter(fn ($o) => $chosen->contains($o->id))->values();
            $matched = $matched->merge($picked->pluck('id'));

            $this->checkCount($picked->count(), (bool) ($group->is_required || $group->is_variant), (int) ($group->max_select ?: 1), $i);

            if ($group->is_variant) {
                $size = $picked->first();
                if ($size !== null) {
                    $baseMinor = self::minor($size->discounted_price ?? $size->price);
                    $variant = self::name($size, $lang);
                }

                continue;
            }
            foreach ($picked as $option) {
                $addonsMinor += self::minor($option->price);
                $extras[] = self::name($option, $lang);
            }
        }

        if ($matched->count() !== $chosen->count()) {
            // An id that is not an available option of THIS item: switched
            // off, deleted, or another item's. Never priced at zero.
            $this->refuse("items.$i.option_ids", 'menu_option_unavailable');
        }

        return $this->row('item', $item->id, self::name($item, $lang), $variant, $extras, $chosen->all(), $line, $baseMinor + $addonsMinor);
    }

    /** @param Collection<int, Combo> $combos */
    private function priceCombo(Collection $combos, array $line, string $lang, int $i): array
    {
        $combo = $combos->get((int) ($line['combo_id'] ?? 0));
        if ($combo === null) {
            $this->refuse("items.$i.combo_id", 'menu_item_unavailable');
        }

        $chosen = collect($line['option_ids'] ?? [])->map(fn ($id) => (int) $id)->unique()->values();
        $baseMinor = self::minor($combo->base_price);
        $addonsMinor = 0;
        $variant = null;
        $extras = [];
        $matched = collect();

        foreach ($combo->groups as $group) {
            $picked = $group->items->filter(fn ($it) => $chosen->contains($it->id))->values();
            $matched = $matched->merge($picked->pluck('id'));

            // Every combo group must be answered — the menu enforces the same.
            $this->checkCount($picked->count(), true, (int) ($group->max_select ?: 1), $i);

            foreach ($picked as $choice) {
                $label = $choice->menuItem ? self::name($choice->menuItem, $lang) : null;
                if ($group->is_variant) {
                    $baseMinor = self::minor($choice->extra_price);
                    $variant = $label;

                    continue;
                }
                $addonsMinor += self::minor($choice->extra_price);
                if ($label !== null) {
                    $extras[] = $label;
                }
            }
        }

        if ($matched->count() !== $chosen->count()) {
            $this->refuse("items.$i.option_ids", 'menu_option_unavailable');
        }

        return $this->row('combo', $combo->id, self::name($combo, $lang), $variant, $extras, $chosen->all(), $line, $baseMinor + $addonsMinor);
    }

    private function checkCount(int $picked, bool $mustAnswer, int $max, int $i): void
    {
        if (($mustAnswer && $picked < 1) || $picked > $max) {
            $this->refuse("items.$i.option_ids", 'menu_option_choice_invalid');
        }
    }

    /** @param list<int> $optionIds */
    private function row(string $kind, int $id, ?string $name, ?string $variant, array $extras, array $optionIds, array $line, int $unitMinor): array
    {
        $qty = (int) $line['qty'];

        $row = [
            'kind' => $kind,
            $kind === 'combo' ? 'combo_id' : 'menu_item_id' => $id,
            'option_ids' => $optionIds,
            'name' => (string) $name,
            'qty' => $qty,
            'options' => $extras,
            'note' => $line['note'] ?? null,
            'unit_price_minor' => $unitMinor,
            'line_total_minor' => $unitMinor * $qty,
            'price_source' => 'server',
        ];
        // Present only when a size was chosen, as the line read before: the
        // stored shape the dashboard reads does not change.
        if ($variant !== null) {
            $row['variant'] = $variant;
        }

        return $row;
    }

    private static function name(object $model, string $lang): ?string
    {
        $primary = $lang === 'ar' ? $model->name_ar : $model->name_en;
        $other = $lang === 'ar' ? $model->name_en : $model->name_ar;

        return filled($primary) ? $primary : $other;
    }

    /** Decimal money to minor units, half-up, never through a float sum. */
    private static function minor(mixed $amount): int
    {
        return (int) round(((float) ($amount ?? 0)) * 100);
    }

    private static function major(int $minor): string
    {
        return number_format($minor / 100, 2, '.', '');
    }

    /** @return never */
    private function refuse(string $field, string $messageKey): void
    {
        throw ValidationException::withMessages([$field => __("xorder.messages.$messageKey")]);
    }
}
