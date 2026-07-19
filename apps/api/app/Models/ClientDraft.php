<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * An in-progress client-creation wizard. Owned by the Super Admin who started
 * it (not a tenant — there is no restaurant yet), so it is intentionally not
 * tenant-scoped.
 */
class ClientDraft extends Model
{
    protected $fillable = [
        'created_by',
        'current_step',
        'form_data',
        'expires_at',
    ];

    protected function casts(): array
    {
        return [
            'form_data' => 'array',
            'expires_at' => 'datetime',
        ];
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
