<?php

namespace App\Http\Requests\Dashboard;

use App\Support\ContentLanguages;
use App\Http\Requests\Concerns\GeofenceValidation;
use App\Rules\MobileNumber;
use Illuminate\Foundation\Http\FormRequest;

class StoreBranchRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('branches.create') ?? false;
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
            'is_open' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            ContentLanguages::checkName($this, $validator, 'xorder.validation.restaurant_name_required');
            GeofenceValidation::check($this, $validator);
        });
    }
}
