<?php

namespace App\Services;

use App\Enums\CurrencyEnum;
use App\Models\Branch;
use App\Models\Charge;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Models\TaxRule;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

/**
 * Server-side pricing (POS-BE-006). Client prices are COMPARED, never used —
 * with the one contractual exception of a line whose menu_item_id no longer
 * resolves (deleted during an outage), which is accepted from name_snapshot +
 * the client's asserted unit price and flagged `price_source: client_asserted`.
 *
 * All arithmetic is integer minor units (D1); rates are basis points. The
 * computation, in order:
 *
 *   unit_price  = variant option's effective price if a variant was chosen
 *                 (explicitly, or detected inside option_ids — 2026-09-02
 *                 amendment), else the item's displayPricing() figure;
 *                 + each add-on option's effective price;
 *                 price_override replaces all of that.
 *   line_total  = unit_price * qty − line discount
 *   subtotal    = Σ (unit_price * qty)                       [gross]
 *   discount    = Σ line discounts + order discount
 *   base        = subtotal − discount                        [floor 0]
 *   charges     = per Charge row scoped to order type/branch: percent on
 *                 base (rate_bp), or fixed amount_minor
 *   tax         = exclusive rules ADD on (base + taxable charges);
 *                 inclusive rules report the contained portion without adding.
 *                 Category-/item-scoped rules apply to matching line totals.
 *   total       = base + charges + exclusive tax
 *
 * tax_minor reports ALL tax (exclusive + extracted inclusive) — it is the
 * receipt's tax line; only the exclusive share moves the total.
 */
class PosPricingEngine
{
    /**
     * @param  list<array<string,mixed>>  $lines
     * @return array{lines: list<array<string,mixed>>, totals: array<string,int>}
     */
    public function price(
        Branch $branch,
        string $orderType,
        array $lines,
        int $orderDiscountMinor,
        CurrencyEnum $currency,
    ): array {
        $exp = 10 ** $currency->exponent();

        $autoGroups = OptionGroup::autoApplied()
            ->with(['options', 'categories:id'])
            ->orderBy('name_en')->orderBy('name_ar')->orderBy('id')
            ->get();

        $items = MenuItem::withTrashed()
            ->whereIn('id', array_values(array_filter(array_column($lines, 'menu_item_id'))))
            ->with(['optionGroups.options', 'sharedOptionGroups.options'])
            ->get()
            ->each(fn (MenuItem $i) => $i->withAutoOptionGroups($autoGroups))
            ->keyBy('id');

        $pricedLines = [];
        $subtotal = 0;
        $lineDiscounts = 0;

        foreach (array_values($lines) as $index => $line) {
            $item = isset($line['menu_item_id']) ? $items->get($line['menu_item_id']) : null;
            $quantity = (int) $line['quantity'];

            if ($item === null || $item->trashed()) {
                // Deleted during an outage: money was taken, honour the sale
                // from the snapshot, flagged so reconciliation can see it.
                $unit = (int) ($line['unit_price_minor'] ?? 0);
                // R1: no item to resolve (deleted during an outage). The single
                // POS snapshot is all we have, so write it into both language
                // slots — the display path always has something to show.
                $snapshot = (string) ($line['name_snapshot'] ?? __('xorder.pos.unknown_item'));
                $priced = [
                    'menu_item_id' => null,
                    'category_id' => null,
                    'name' => $snapshot,
                    'name_ar' => $snapshot,
                    'name_en' => $snapshot,
                    'options' => [],
                    'price_source' => 'client_asserted',
                ];
            } else {
                [$unit, $optionNames] = $this->unitPrice($item, $line, $exp, $index);
                $priced = [
                    'menu_item_id' => $item->id,
                    'category_id' => $item->category_id,
                    // R1: the server is the naming authority for a resolved
                    // item — freeze BOTH languages from it. The till's
                    // name_snapshot is advisory and no longer wins here.
                    'name' => $item->name_en ?: $item->name_ar,
                    'name_ar' => $item->name_ar,
                    'name_en' => $item->name_en,
                    'options' => $optionNames,
                    'price_source' => 'server',
                ];
            }

            if (isset($line['price_override'])) {
                $unit = (int) $line['price_override']['unit_price_minor'];
                $priced['price_source'] = 'override';
            }

            $gross = $unit * $quantity;
            $discount = (int) ($line['discount']['amount_minor'] ?? 0);
            $discount = min($discount, $gross);

            $priced += [
                // Carried through untouched (POS-BE-010): it is the till's
                // name for the line, not a priced fact, and the refund path
                // addresses lines by it.
                'client_line_id' => isset($line['client_line_id']) && $line['client_line_id'] !== ''
                    ? (string) $line['client_line_id']
                    : null,
                'quantity' => $quantity,
                'note' => $line['note'] ?? null,
                'unit_price_minor' => $unit,
                'discount_minor' => $discount,
                'line_total_minor' => $gross - $discount,
            ];

            $subtotal += $gross;
            $lineDiscounts += $discount;
            $pricedLines[] = $priced;
        }

        $discountMinor = $lineDiscounts + max(0, $orderDiscountMinor);
        $base = max(0, $subtotal - $discountMinor);

        [$chargesMinor, $taxableCharges] = $this->charges($branch, $orderType, $base);
        [$taxMinor, $exclusiveTax] = $this->tax($branch, $orderType, $base, $taxableCharges, $pricedLines);

        return [
            'lines' => $pricedLines,
            'totals' => [
                'subtotal_minor' => $subtotal,
                'discount_minor' => $discountMinor,
                'tax_minor' => $taxMinor,
                'charges_minor' => $chargesMinor,
                'total_minor' => $base + $chargesMinor + $exclusiveTax,
            ],
        ];
    }

    /**
     * @return array{0: int, 1: list<string>} unit price minor + option labels
     */
    private function unitPrice(MenuItem $item, array $line, int $exp, int $index): array
    {
        $groups = $item->orderedOptionGroups();

        /** @var Collection<int, array{option: object, group: object}> $optionMap */
        $optionMap = collect();
        foreach ($groups as $group) {
            foreach ($group->options as $option) {
                $optionMap->put($option->id, ['option' => $option, 'group' => $group]);
            }
        }

        $optionIds = array_map('intval', $line['option_ids'] ?? []);
        $variantId = isset($line['variant_option_id']) ? (int) $line['variant_option_id'] : null;

        // 2026-09-02 amendment: the variant may arrive inside option_ids[].
        // Detect it there; two variant options of one group is a client bug.
        $variantsSeen = []; // group_id => option_id
        $addOns = [];

        foreach ($optionIds as $id) {
            $entry = $optionMap->get($id);

            if ($entry === null) {
                throw ValidationException::withMessages([
                    "lines.$index.option_ids" => ["Option $id does not apply to this item."],
                ]);
            }

            if ($entry['group']->is_variant) {
                if (isset($variantsSeen[$entry['group']->id]) && $variantsSeen[$entry['group']->id] !== $id) {
                    throw ValidationException::withMessages([
                        "lines.$index.option_ids" => ['Two variant options of the same group were sent.'],
                    ]);
                }
                $variantsSeen[$entry['group']->id] = $id;
            } else {
                $addOns[] = $entry;
            }
        }

        if ($variantId !== null) {
            $entry = $optionMap->get($variantId);
            if ($entry === null || ! $entry['group']->is_variant) {
                throw ValidationException::withMessages([
                    "lines.$index.variant_option_id" => ['Not a variant option of this item.'],
                ]);
            }
            if (isset($variantsSeen[$entry['group']->id]) && $variantsSeen[$entry['group']->id] !== $variantId) {
                throw ValidationException::withMessages([
                    "lines.$index.variant_option_id" => ['Conflicts with the variant sent in option_ids.'],
                ]);
            }
            $variantsSeen[$entry['group']->id] = $variantId;
        }

        // Base: the chosen variant REPLACES the item price; with none chosen,
        // displayPricing() already answers "what does an untouched add pay"
        // (the default size on a variant-priced item, the item's own column
        // otherwise).
        if ($variantsSeen !== []) {
            $chosen = $optionMap->get(reset($variantsSeen))['option'];
            $unit = $this->toMinor($chosen->discounted_price ?? $chosen->price, $exp);
        } else {
            [$price, $discounted] = $item->displayPricing();
            $unit = $this->toMinor($discounted ?? $price, $exp);
        }

        $labels = [];
        foreach ($variantsSeen as $optionId) {
            $labels[] = $this->optionLabel($optionMap->get($optionId)['option']);
        }
        foreach ($addOns as $entry) {
            $unit += $this->toMinor($entry['option']->price, $exp);
            $labels[] = $this->optionLabel($entry['option']);
        }

        return [$unit, $labels];
    }

    /** @return array{0: int, 1: int} total charges + the taxable share */
    private function charges(Branch $branch, string $orderType, int $base): array
    {
        $total = 0;
        $taxable = 0;

        foreach (Charge::orderBy('sort_order')->orderBy('id')->get() as $charge) {
            if (! $this->scopeMatches($charge->applies_to, $orderType, $branch->id)) {
                continue;
            }

            $amount = $charge->kind === 'percent'
                ? intdiv($base * $charge->rate_bp + 5000, 10000)
                : (int) $charge->amount_minor;

            $total += $amount;
            if ($charge->taxable) {
                $taxable += $amount;
            }
        }

        return [$total, $taxable];
    }

    /** @return array{0: int, 1: int} all tax (receipt line) + the exclusive share (moves the total) */
    private function tax(Branch $branch, string $orderType, int $base, int $taxableCharges, array $lines): array
    {
        $all = 0;
        $exclusive = 0;

        foreach (TaxRule::orderBy('sort_order')->orderBy('id')->get() as $rule) {
            if (! $this->scopeMatches($rule->applies_to, $orderType, $branch->id)) {
                continue;
            }

            $taxBase = $this->ruleBase($rule, $base, $taxableCharges, $lines);

            if ($rule->mode === 'inclusive') {
                // The contained portion of an inclusive price: b*r/(10000+r).
                $all += intdiv($taxBase * $rule->rate_bp + intdiv(10000 + $rule->rate_bp, 2), 10000 + $rule->rate_bp);
            } else {
                $amount = intdiv($taxBase * $rule->rate_bp + 5000, 10000);
                $all += $amount;
                $exclusive += $amount;
            }
        }

        return [$all, $exclusive];
    }

    /** Category-/item-scoped rules bite on matching lines; unscoped on the whole base. */
    private function ruleBase(TaxRule $rule, int $base, int $taxableCharges, array $lines): int
    {
        $scope = $rule->applies_to ?? [];
        $categoryIds = $scope['category_ids'] ?? [];
        $itemIds = $scope['item_ids'] ?? [];

        if ($categoryIds === [] && $itemIds === []) {
            return $base + $taxableCharges;
        }

        $sum = 0;
        foreach ($lines as $line) {
            $inCategory = $categoryIds !== [] && in_array($line['category_id'], $categoryIds, true);
            $inItems = $itemIds !== [] && in_array($line['menu_item_id'], $itemIds, true);
            if ($inCategory || $inItems) {
                $sum += $line['line_total_minor'];
            }
        }

        return $sum;
    }

    private function scopeMatches(?array $scope, string $orderType, int $branchId): bool
    {
        $orderTypes = $scope['order_types'] ?? [];
        $branchIds = $scope['branch_ids'] ?? [];

        return ($orderTypes === [] || in_array($orderType, $orderTypes, true))
            && ($branchIds === [] || in_array($branchId, array_map('intval', $branchIds), true));
    }

    /** decimal(10,2) string → integer minor units, exactly. */
    private function toMinor(mixed $decimal, int $exp): int
    {
        return (int) round(((float) $decimal) * $exp);
    }

    private function optionLabel(object $option): string
    {
        return (string) ($option->name_en ?: $option->name_ar);
    }
}
