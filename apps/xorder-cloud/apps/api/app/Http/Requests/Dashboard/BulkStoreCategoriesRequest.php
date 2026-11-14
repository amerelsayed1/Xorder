<?php

namespace App\Http\Requests\Dashboard;

use App\Support\ContentLanguages;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Several categories in one request (XORD-007). The whole batch is validated
 * first and stored in one transaction by the controller: one bad row refuses
 * all of them, so a retry never leaves half a menu behind.
 */
class BulkStoreCategoriesRequest extends FormRequest
{
    /** Most rows one request may carry. */
    public const MAX_ROWS = 50;

    public function authorize(): bool
    {
        return $this->user()?->can('menu.create') ?? false;
    }

    protected function prepareForValidation(): void
    {
        $rows = $this->input('categories');
        if (! is_array($rows)) {
            return;
        }

        // Names are compared trimmed: "Drinks " and "Drinks" are one category.
        $this->merge(['categories' => array_map(function ($row) {
            if (! is_array($row)) {
                return $row;
            }
            foreach (['name_ar', 'name_en'] as $field) {
                if (isset($row[$field]) && is_string($row[$field])) {
                    $trimmed = trim($row[$field]);
                    $row[$field] = $trimmed === '' ? null : $trimmed;
                }
            }

            return $row;
        }, $rows)]);
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;

        return [
            'categories' => ['required', 'array', 'min:1', 'max:'.self::MAX_ROWS],
            'categories.*.name_ar' => [
                'nullable', 'string', 'max:150',
                Rule::unique('categories', 'name_ar')->where('restaurant_id', $restaurantId)->whereNull('deleted_at'),
            ],
            'categories.*.name_en' => [
                'nullable', 'string', 'max:150',
                Rule::unique('categories', 'name_en')->where('restaurant_id', $restaurantId)->whereNull('deleted_at'),
            ],
            'categories.*.is_active' => ['nullable', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            $rows = $this->input('categories');
            if (! is_array($rows)) {
                return;
            }

            // Judged by the restaurant's content languages and attached to the
            // field its form renders, so the error is visible.
            $languages = ContentLanguages::of($this->user()->restaurant);

            $seen = ['name_ar' => [], 'name_en' => []];
            foreach ($rows as $index => $row) {
                if (! is_array($row)) {
                    continue;
                }

                if (($blame = $languages->missingName($row['name_ar'] ?? null, $row['name_en'] ?? null, primaryWhenBilingual: true)) !== null) {
                    $validator->errors()->add("categories.{$index}.{$blame}", __('xorder.validation.category_name_required'));

                    continue;
                }

                foreach (['name_ar', 'name_en'] as $field) {
                    $name = $row[$field] ?? null;
                    if (blank($name)) {
                        continue;
                    }
                    if (isset($seen[$field][$name])) {
                        $validator->errors()->add("categories.{$index}.{$field}", __('xorder.validation.category_duplicate_in_batch', ['name' => $name]));

                        continue;
                    }
                    $seen[$field][$name] = $index;
                }
            }
        });
    }
}
