<?php

namespace App\Http\Requests\Concerns;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

/**
 * Cross-field rule for a size/variant option's sale price: it must undercut the
 * option's own price, mirroring the item-level `discounted_price < price` rule.
 *
 * Written as an after-callback rather than an `lt:` rule because the compared
 * field (`…options.*.price`) is only `sometimes` present — Laravel's `lt`
 * throws when the other side is missing, which would turn a malformed payload
 * into a 500 instead of a 422.
 */
class OptionDiscountValidation
{
    /** Options nested under an item's groups: option_groups.{g}.options.{o}. */
    public static function checkItemGroups(FormRequest $request, Validator $validator): void
    {
        foreach ((array) $request->input('option_groups', []) as $gi => $group) {
            self::checkList($validator, (array) ($group['options'] ?? []), "option_groups.{$gi}.options");
        }
    }

    /** A shared library group's own flat list: options.{o}. */
    public static function checkGroup(FormRequest $request, Validator $validator): void
    {
        self::checkList($validator, (array) $request->input('options', []), 'options');
    }

    private static function checkList(Validator $validator, array $options, string $prefix): void
    {
        foreach ($options as $oi => $option) {
            $discount = is_array($option) ? ($option['discounted_price'] ?? null) : null;

            // Absent, or already failing the numeric rule — nothing to compare.
            if (! is_numeric($discount)) {
                continue;
            }

            $price = is_array($option) ? ($option['price'] ?? 0) : 0;
            if (! is_numeric($price) || (float) $discount >= (float) $price) {
                $validator->errors()->add(
                    "{$prefix}.{$oi}.discounted_price",
                    __('xorder.validation.discounted_price_lt')
                );
            }
        }
    }
}
