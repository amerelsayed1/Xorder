<?php

namespace App\Http\Requests\Dashboard;

use App\Services\UnitCatalog;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09 slice b: a stock item. A name in at least one language, a unit by
 * CODE (this business's, active), and an optional link to one of this
 * business's menu items, which no other stock item already counts.
 *
 * The units are seeded first: a business may create its first stock item
 * before it ever opened the Units page, and the seven defaults must exist
 * for `kg` to validate.
 */
class StoreStockItemRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        app(UnitCatalog::class)->ensureDefaults($this->user()->restaurant_id);

        $merge = [];
        if ($this->has('sku')) {
            $sku = is_string($this->input('sku')) ? trim($this->input('sku')) : $this->input('sku');
            $merge['sku'] = $sku === '' ? null : $sku;
        }
        if (is_string($this->input('unit_code'))) {
            $merge['unit_code'] = strtolower(trim($this->input('unit_code')));
        }
        $this->merge($merge);
    }

    public function rules(): array
    {
        $tenant = $this->user()->restaurant_id;
        $current = $this->route('stockItem');

        return [
            'name_en' => ['nullable', 'string', 'max:160'],
            'name_ar' => ['nullable', 'string', 'max:160'],
            'sku' => ['nullable', 'string', 'max:64'],
            'unit_code' => [
                $current ? 'sometimes' : 'required', 'string',
                // A retired unit is refused, except the one the item already has.
                Rule::exists('units', 'code')->where(fn ($q) => $q->where('restaurant_id', $tenant)
                    ->where(fn ($q) => $q->where('is_active', true)->when($current, fn ($q) => $q->orWhere('code', $current->unit_code)))),
            ],
            'menu_item_id' => [
                'nullable', 'integer',
                Rule::exists('menu_items', 'id')->where('restaurant_id', $tenant)->whereNull('deleted_at'),
                Rule::unique('stock_items', 'menu_item_id')->ignore($current),
            ],
            'is_active' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if (blank($this->input('name_en')) && blank($this->input('name_ar'))) {
                $validator->errors()->add('name_en', __('xorder.validation.stock_item_name_required'));
            }
        });
    }

    public function messages(): array
    {
        return [
            'unit_code.exists' => __('xorder.validation.stock_item_unit'),
            'menu_item_id.unique' => __('xorder.validation.stock_item_menu_item_taken'),
        ];
    }
}
