<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * XORD-015: the account a payment method pays into at one branch
 * (`branch_id` null = the business-wide fallback). See the migration for why
 * `branch_key` exists.
 */
class TenderAccountDefault extends Model
{
    use Auditable, BelongsToRestaurant;

    protected $fillable = ['tender_type_id', 'branch_id', 'financial_account_id'];

    protected static function booted(): void
    {
        static::saving(function (self $row): void {
            $row->branch_key = (int) ($row->branch_id ?? 0);
        });
    }

    /**
     * The activity line for a default has to say which method pays into which
     * account at which branch: this is a money-routing setting, and the
     * generic label would read `"#9" created`. Resolved without the tenant
     * scope's help being needed, because the audit runs inside the request.
     */
    protected function auditLabel(): string
    {
        $method = $this->tenderType?->name ?? '#'.$this->tender_type_id;
        $account = $this->financialAccount?->name ?? '#'.$this->financial_account_id;
        $where = $this->branch_id === null ? 'all branches' : 'branch #'.$this->branch_id;

        return sprintf('%s pays into %s (%s)', $method, $account, $where);
    }

    public function tenderType(): BelongsTo
    {
        return $this->belongsTo(TenderType::class);
    }

    public function financialAccount(): BelongsTo
    {
        return $this->belongsTo(FinancialAccount::class);
    }
}
