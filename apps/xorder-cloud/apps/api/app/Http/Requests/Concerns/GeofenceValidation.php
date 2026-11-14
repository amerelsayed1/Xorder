<?php

namespace App\Http\Requests\Concerns;

use App\Support\GeoFence;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

/**
 * Shared cross-field rule for the branch geofence: you can only turn the fence
 * ON once a real area (>= 3 vertices) has been drawn — otherwise "enabled" with
 * no polygon would silently trap every diner (an empty fence contains no one).
 */
class GeofenceValidation
{
    public static function check(FormRequest $request, Validator $validator): void
    {
        if (! $request->boolean('geofence_enabled')) {
            return;
        }

        if (! GeoFence::isEnforceable($request->input('geofence'))) {
            $validator->errors()->add('geofence', __('xorder.validation.geofence_required'));
        }
    }
}
