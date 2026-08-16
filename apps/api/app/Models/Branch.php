<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use App\Traits\NormalizesPhoneNumbers;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;

class Branch extends Model
{
    use Auditable, BelongsToRestaurant, NormalizesPhoneNumbers;

    protected $fillable = [
        'name_ar',
        'name_en',
        'code',
        'address',
        'address_ar',
        'address_en',
        'city',
        'country',
        'phone',
        'whatsapp_number',
        'opening_hours',
        'business_hours',
        'map_url',
        'latitude',
        'longitude',
        'geofence',
        'geofence_enabled',
        'is_open',
        'is_active',
        'supported_order_types',
        'sort_order',
    ];

    /**
     * Learned, machine-written columns — excluded so the nightly egress-IP
     * refresh doesn't spam the audit log with a "branch updated" entry per run.
     *
     * @var list<string>
     */
    protected array $auditExclude = ['egress_ips', 'egress_ips_learned_at'];

    protected function casts(): array
    {
        return [
            'is_open' => 'boolean',
            'is_active' => 'boolean',
            'business_hours' => 'array',
            'latitude' => 'float',
            'longitude' => 'float',
            'geofence' => 'array',
            'geofence_enabled' => 'boolean',
            'supported_order_types' => 'array',
            // Learned addresses — deliberately absent from $fillable: written
            // only by BranchEgressIpService, never from request input.
            'egress_ips' => 'array',
            'egress_ips_learned_at' => 'datetime',
            // Owner-declared addresses. Set through a dedicated endpoint rather
            // than the branch form, so a normal branch update can never touch
            // them by accident, and audited (unlike the learned list) because a
            // person changed it.
            'egress_ips_manual' => 'array',
        ];
    }

    protected function phone(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $this->normalizePhoneDigits($value),
        );
    }

    protected function whatsappNumber(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $this->normalizePhoneDigits($value),
        );
    }

    private function normalizePhoneDigits(?string $value): ?string
    {
        if (is_null($value)) {
            return null;
        }

        $arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
        $englishDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
        $persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

        $value = str_replace($arabicDigits, $englishDigits, $value);

        return str_replace($persianDigits, $englishDigits, $value);
    }
}
