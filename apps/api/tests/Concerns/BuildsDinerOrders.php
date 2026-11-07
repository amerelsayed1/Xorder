<?php

namespace Tests\Concerns;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Option;
use App\Models\OptionGroup;
use App\Models\Restaurant;

/**
 * Diner order lines the way the menu sends them since XORD-047: by item id.
 *
 * The suites that post orders used to send names and line totals, which the
 * server now refuses (it prices from the menu). This turns such a line into a
 * real menu item priced so the line costs exactly what the test always meant
 * (`line_total / qty`), and returns the id-based line — so each test keeps its
 * meaning and its numbers. A line with a `variant` gets a size group whose one
 * size carries that price, so the size is chosen and the total unchanged.
 */
trait BuildsDinerOrders
{
    /**
     * @param  list<array{name?: string, qty?: int, line_total?: int|float, note?: ?string}>  $lines
     * @return list<array<string,mixed>>
     */
    protected function dinerItems(array $lines, ?Restaurant $restaurant = null): array
    {
        // The restaurant the test made last, when the payload is built in a
        // helper that has none in scope.
        $restaurant ??= Restaurant::query()->latest('id')->firstOrFail();

        $category = Category::factory()->create(['restaurant_id' => $restaurant->id]);

        return array_map(function (array $line) use ($restaurant, $category) {
            $qty = (int) ($line['qty'] ?? 1);
            $unit = round(((float) ($line['line_total'] ?? 10)) / $qty, 2);
            $item = MenuItem::factory()->create([
                'restaurant_id' => $restaurant->id,
                'category_id' => $category->id,
                'name_en' => $line['name'] ?? 'Item',
                'name_ar' => $line['name'] ?? 'صنف',
                'price' => $unit,
            ]);

            $optionIds = [];
            if (filled($line['variant'] ?? null)) {
                $group = new OptionGroup([
                    'menu_item_id' => $item->id,
                    'name_en' => 'Size',
                    'name_ar' => 'الحجم',
                    'is_variant' => true,
                    'is_required' => true,
                    'max_select' => 1,
                ]);
                $group->restaurant_id = $restaurant->id;
                $group->save();
                $size = new Option([
                    'option_group_id' => $group->id,
                    'name_en' => $line['variant'],
                    'name_ar' => $line['variant'],
                    'price' => $unit,
                    'is_available' => true,
                ]);
                $size->restaurant_id = $restaurant->id;
                $size->save();
                $optionIds[] = $size->id;
            }

            return array_filter([
                'kind' => 'item',
                'menu_item_id' => $item->id,
                'option_ids' => $optionIds ?: null,
                'qty' => $qty,
                'note' => $line['note'] ?? null,
            ], fn ($v) => $v !== null);
        }, $lines);
    }
}
