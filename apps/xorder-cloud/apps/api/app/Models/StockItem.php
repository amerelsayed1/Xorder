<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * CB-09 slice b: something a business buys and counts (D3). Its own table,
 * optionally linked to ONE menu item, and never counted against max_items.
 *
 * `unit_code` changes only through StockItemService, which refuses while the
 * item holds stock in any branch or sits on an open order. There is no
 * delete: it is retired with is_active = false.
 */
class StockItem extends Model
{
    use Auditable, BelongsToRestaurant;

    protected $fillable = ['name_en', 'name_ar', 'sku', 'menu_item_id', 'unit_code', 'is_active'];

    protected array $auditExclude = ['updated_by'];

    protected function casts(): array
    {
        return [
            'menu_item_id' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    /** Soft-deleted menu items still resolve, so the link keeps its name. */
    public function menuItem(): BelongsTo
    {
        return $this->belongsTo(MenuItem::class)->withTrashed();
    }

    public function levels(): HasMany
    {
        return $this->hasMany(StockLevel::class);
    }

    public function purchaseOrderLines(): HasMany
    {
        return $this->hasMany(PurchaseOrderLine::class);
    }

    /** Whichever name is set, the business's default language first. */
    public function displayName(?string $preferred = null): string
    {
        $first = $preferred === 'ar' ? $this->name_ar : $this->name_en;
        $second = $preferred === 'ar' ? $this->name_en : $this->name_ar;

        return $first ?: ($second ?: '#'.$this->getKey());
    }

    protected function auditLabel(): string
    {
        return $this->name_en ?: ($this->name_ar ?: '#'.$this->getKey());
    }
}
