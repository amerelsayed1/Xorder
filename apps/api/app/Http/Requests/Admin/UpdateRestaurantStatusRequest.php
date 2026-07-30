<?php

namespace App\Http\Requests\Admin;

use App\Enums\RestaurantStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateRestaurantStatusRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('restaurants.manage') ?? false;
    }

    public function rules(): array
    {
        return [
            'status' => ['required', Rule::enum(RestaurantStatus::class)],
        ];
    }
}
