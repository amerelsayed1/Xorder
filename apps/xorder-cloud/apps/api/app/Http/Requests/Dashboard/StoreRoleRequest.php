<?php

namespace App\Http\Requests\Dashboard;

use App\Http\Requests\Dashboard\Concerns\GrantsTenantCapabilities;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreRoleRequest extends FormRequest
{
    use GrantsTenantCapabilities;

    public function authorize(): bool
    {
        return $this->user()?->can('staff.create') ?? false;
    }

    public function rules(): array
    {
        // Role names are unique inside one restaurant only — two tenants may
        // each have a "Cashier".
        $tenantId = $this->user()?->restaurant_id;

        return [
            'name' => [
                'required', 'string', 'max:80',
                Rule::unique('roles', 'name')->where('restaurant_id', $tenantId),
            ],
            'name_ar' => ['nullable', 'string', 'max:80'],
            'capabilities' => ['required', 'array', 'min:1'],
            'capabilities.*' => ['string', Rule::in($this->capabilityValues())],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(fn (Validator $v) => $this->rejectUngrantable($v, $this->requestedCapabilities()));
    }
}
