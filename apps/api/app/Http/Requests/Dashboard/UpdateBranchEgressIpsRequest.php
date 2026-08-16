<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Replaces a branch's owner-declared customer Wi-Fi addresses.
 *
 * The whole list is sent every time rather than add/remove deltas: it is a
 * handful of entries edited by hand, and a replace has no ordering or
 * partial-failure semantics to get wrong.
 */
class UpdateBranchEgressIpsRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Tenant isolation is structural: the {branch} route binding is scoped
        // by RestaurantScope, so another restaurant's id never resolves here.
        return true;
    }

    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            // Capped low on purpose. A branch has one internet line; several
            // entries means a failover or a second line, not an open list —
            // and a long list would quietly widen what counts as "on premises".
            'egress_ips' => ['present', 'array', 'max:5'],
            'egress_ips.*' => ['required', 'string', 'ip'],
        ];
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        return [
            'egress_ips.*.ip' => __('xorder.validation.egress_ip_invalid'),
            'egress_ips.max' => __('xorder.validation.egress_ips_max'),
        ];
    }
}
