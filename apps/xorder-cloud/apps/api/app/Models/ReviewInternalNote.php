<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ReviewInternalNote extends Model
{
    protected $fillable = [
        'internal_review_id',
        'user_id',
        'note',
    ];

    public function review(): BelongsTo
    {
        return $this->belongsTo(InternalReview::class, 'internal_review_id');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
