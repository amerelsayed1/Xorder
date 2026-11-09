<?php

namespace App\Services;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Models\Restaurant;

/**
 * The menu as the waiter wire (POS-BE-033) shows it: categories, products with
 * a server-computed price, and the modifier groups they use. Combos and
 * open-price items are left out, as the till leaves them out. Tenant scope is
 * the one the waiter middleware pinned.
 */
class WaiterMenuService
{
    /** @return array<string,mixed> */
    public function menu(Restaurant $restaurant): array
    {
        $exp = 10 ** $restaurant->currency->exponent();

        $autoGroups = OptionGroup::autoApplied()
            ->with(['options', 'categories:id'])
            ->orderBy('name_en')->orderBy('name_ar')->orderBy('id')
            ->get();

        $categories = Category::query()
            ->where('is_active', true)
            ->orderBy('display_order')->orderBy('id')
            ->with(['menuItems' => fn ($q) => $q->orderBy('display_order')->orderBy('id')
                ->with(['optionGroups.options', 'sharedOptionGroups.options'])])
            ->get();

        $outCategories = [];
        $products = [];
        $groups = [];

        foreach ($categories as $category) {
            /** @var Category $category */
            if ($category->menuItems->isEmpty()) {
                continue;
            }

            $outCategories[] = ['id' => $category->id, 'name' => $this->name($category)];

            foreach ($category->menuItems as $item) {
                /** @var MenuItem $item */
                $item->withAutoOptionGroups($autoGroups);
                [$price, $discounted] = $item->displayPricing();
                $base = $this->minor($discounted ?? $price, $exp);
                $groupIds = [];

                foreach ($item->orderedOptionGroups() as $group) {
                    $groupIds[] = $group->id;
                    $groups[$group->id] ??= $this->group($group, $base, $exp);
                }

                $products[] = [
                    'id' => $item->id,
                    'category_id' => $category->id,
                    'name' => $this->name($item),
                    'price_minor' => $base,
                    'available' => (bool) $item->is_available,
                    'groups' => $groupIds,
                ];
            }
        }

        return [
            'currency' => ['code' => $restaurant->currency->value, 'exponent' => $restaurant->currency->exponent()],
            'categories' => $outCategories,
            'products' => $products,
            'groups' => array_values($groups),
        ];
    }

    /** @return array<string,mixed> */
    private function group(OptionGroup $group, int $base, int $exp): array
    {
        $isVariant = (bool) $group->is_variant;
        $options = $group->options;
        $firstAvailable = $options->firstWhere('is_available', true)?->id;

        $modifiers = [];
        foreach ($options as $option) {
            $price = $this->minor($option->discounted_price ?? $option->price, $exp);

            $modifiers[] = [
                'id' => $option->id,
                'name' => $this->name($option),
                // A variant REPLACES the item price, so its delta is relative to
                // the price the product shows; an add-on adds its own price.
                'delta_minor' => $isVariant ? $price - $base : $price,
                'available' => (bool) $option->is_available,
                'default' => $isVariant && $option->id === $firstAvailable,
            ];
        }

        return [
            'id' => $group->id,
            'name' => ['en' => (string) ($group->name_en ?: $group->name_ar), 'ar' => $group->name_ar],
            'min' => $group->is_required ? 1 : 0,
            'max' => (int) ($group->max_select ?: ($isVariant ? 1 : max(1, count($modifiers)))),
            'variant' => $isVariant,
            'modifiers' => $modifiers,
        ];
    }

    /** @return array{en: string, ar: ?string} */
    private function name(object $model): array
    {
        return [
            'en' => (string) ($model->name_en ?: $model->name_ar),
            'ar' => $model->name_ar ?: null,
        ];
    }

    private function minor(mixed $decimal, int $exp): int
    {
        return (int) round((float) $decimal * $exp);
    }
}
