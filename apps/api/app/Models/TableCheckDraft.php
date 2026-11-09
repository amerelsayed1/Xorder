<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * The unsent lines of one table visit (POS-BE-033): one draft per visit,
 * shared by every device at the table. Lines hold ids and quantities only —
 * never a price; the server prices them on every read.
 */
class TableCheckDraft extends Model
{
    protected $guarded = [];

    protected function casts(): array
    {
        return ['lines' => 'array', 'guests' => 'integer'];
    }
}
