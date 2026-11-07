<?php

namespace App\Http\Requests\Dashboard;

use App\Http\Requests\Concerns\GeofenceValidation;
use App\Rules\MobileNumber;
use App\Services\BranchEgressIpService;
use App\Services\OrderTypeEntitlements;
use App\Support\ContentLanguages;
use App\Http\Requests\Concerns\PreservesDisabledLanguages;
use Illuminate\Foundation\Http\FormRequest;

class UpdateBranchRequest extends FormRequest
{
    use PreservesDisabledLanguages;

    protected function translatedFields(): array
    {
        return ['name'];
    }

    public function authorize(): bool
    {
        if (! ($this->user()?->can('branches.update') ?? false)) {
            return false;
        }

        // Changing which order types a branch offers is its own permission
        // (XORD-002). A form that merely posts the list back unchanged — every
        // branch edit does — is not a change and needs nothing extra.
        return ! $this->changesOrderTypes()
            || $this->user()->can('pos.settings.order_types.manage');
    }

    /**
     * The order types the request would store, in the till's spelling, or null
     * when it does not touch them.
     *
     * @return list<string>|null
     */
    public function requestedOrderTypes(): ?array
    {
        if (! $this->has('supported_order_types')) {
            return null;
        }

        return OrderTypeEntitlements::normalise((array) ($this->input('supported_order_types') ?? []));
    }

    public function changesOrderTypes(): bool
    {
        $requested = $this->requestedOrderTypes();
        if ($requested === null) {
            return false;
        }

        $stored = OrderTypeEntitlements::normalise($this->route('branch')->supported_order_types ?? []);

        return $requested !== $stored;
    }

    public function rules(): array
    {
        return [
            'name_ar' => ['nullable', 'string', 'max:150'],
            'name_en' => ['nullable', 'string', 'max:150'],
            'address' => ['nullable', 'string', 'max:1000'],
            'phone' => ['nullable', 'string', 'max:32', (new MobileNumber)->allowLandline()],
            'whatsapp_number' => ['nullable', 'string', 'max:32', new MobileNumber],
            'opening_hours' => ['nullable', 'string', 'max:500'],
            'business_hours' => ['nullable', 'array'],
            'business_hours.*.closed' => ['sometimes', 'boolean'],
            'business_hours.*.always' => ['sometimes', 'boolean'],
            'business_hours.*.open' => ['nullable', 'date_format:H:i'],
            'business_hours.*.close' => ['nullable', 'date_format:H:i'],
            'map_url' => ['nullable', 'url', 'max:2048'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            // Presence geofence: either a drawn polygon or a radius circle.
            'geofence' => ['nullable', 'array'],
            'geofence.type' => ['required_with:geofence', 'in:polygon,radius'],
            'geofence.points' => ['required_if:geofence.type,polygon', 'array', 'max:500'],
            'geofence.points.*.lat' => ['required_with:geofence.points', 'numeric', 'between:-90,90'],
            'geofence.points.*.lng' => ['required_with:geofence.points', 'numeric', 'between:-180,180'],
            'geofence.center' => ['required_if:geofence.type,radius', 'array'],
            'geofence.center.lat' => ['required_with:geofence.center', 'numeric', 'between:-90,90'],
            'geofence.center.lng' => ['required_with:geofence.center', 'numeric', 'between:-180,180'],
            'geofence.radius' => ['required_if:geofence.type,radius', 'numeric', 'min:10', 'max:20000'],
            'geofence_enabled' => ['sometimes', 'boolean'],
            // Hard Wi-Fi gate for table scans — see the guard in withValidator.
            'require_branch_wifi' => ['sometimes', 'boolean'],
            'is_open' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
            // POS-BE-005: which order types this branch takes. [] means "all"
            // (PosOrderService only refuses when the list is non-empty), so an
            // empty array is a valid, permissive value and never "none".
            //
            // `pickup` is accepted alongside the four POS types because the
            // Super Admin onboarding wizard writes it (there the value mirrors
            // the plan's ordering-channel feature keys: dine_in / pickup /
            // delivery). Rejecting it would make every branch created through
            // that wizard unsaveable from the branch form.
            'supported_order_types' => ['nullable', 'array'],
            'supported_order_types.*' => ['string', 'in:dine_in,takeaway,delivery,drive_thru,pickup'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            ContentLanguages::checkName($this, $validator, 'xorder.validation.restaurant_name_required', partial: true);
            GeofenceValidation::check($this, $validator);

            $this->checkOrderTypes($validator);

            // Turning the Wi-Fi requirement on with no address on file would
            // refuse every table scan at this branch with nothing an owner
            // could do from off-site — the enforcement fails closed on the
            // "we have no idea" answer. Refuse the switch instead of letting
            // it produce an outage that looks like a bug.
            if ($this->boolean('require_branch_wifi')
                && app(BranchEgressIpService::class)->knownAddresses($this->route('branch')) === []) {
                $validator->errors()->add(
                    'require_branch_wifi',
                    __('xorder.validation.branch_wifi_requires_address')
                );
            }
        });
    }

    /**
     * Only a CHANGE is judged, so a branch that already holds something the plan
     * no longer includes can still be renamed. A change must leave at least one
     * type on, and may only switch on what the subscription includes.
     */
    private function checkOrderTypes($validator): void
    {
        if (! $this->changesOrderTypes()) {
            return;
        }

        $requested = $this->requestedOrderTypes();
        if ($requested === []) {
            $validator->errors()->add('supported_order_types', __('xorder.validation.order_types_at_least_one'));

            return;
        }

        $stored = OrderTypeEntitlements::normalise($this->route('branch')->supported_order_types ?? []);
        $allowed = app(OrderTypeEntitlements::class)->allowed($this->user()->restaurant);
        $notIncluded = array_values(array_diff(array_diff($requested, $stored), $allowed));

        if ($notIncluded !== []) {
            $validator->errors()->add('supported_order_types', __('xorder.validation.order_types_not_in_plan', [
                'types' => implode(', ', $notIncluded),
            ]));
        }
    }
}
