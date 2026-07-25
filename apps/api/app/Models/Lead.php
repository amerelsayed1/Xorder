<?php

namespace App\Models;

use App\Enums\LeadStatus;
use App\Traits\NormalizesPhoneNumbers;
use Illuminate\Database\Eloquent\Model;

class Lead extends Model
{
    use NormalizesPhoneNumbers;

    protected $fillable = [
        'restaurant_name',
        'contact_name',
        'whatsapp',
        'city',
        'business_type',
        'message',
        'source',
        'status',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'status' => LeadStatus::class,
        ];
    }
}
