<?php

namespace App\Services;

use App\Models\Branch;
use App\Models\ReceiptProfile;
use App\Models\Restaurant;
use Illuminate\Support\Collection;

/**
 * A3 — the receipt profile on the wire, in one place, so the dashboard shows
 * exactly what a till will print.
 *
 * **Every branch gets a profile, whether or not one was ever authored.** A
 * cloud till that receives no row for its branch falls back to compiled-in
 * defaults, which is the bug A3 exists to fix, so an unauthored branch is
 * projected here from what the platform already knows: the restaurant's name
 * as the trade name, the restaurant's tax registration number, country EG, and
 * empty strings for the rest. `revision: 0` says "nobody has typed this yet".
 *
 * Empty strings, never nulls: the till's `pos_receipt_profiles` columns are
 * NOT NULL DEFAULT '', so a straight snake_case mapping in its seeder needs no
 * null handling. The two free-text notes are the exception — they are
 * genuinely absent rather than empty, and the till's model has them nullable.
 */
class ReceiptProfileService
{
    /**
     * One row per branch, in branch id order.
     *
     * @param  Collection<int,Branch>  $branches
     * @return list<array<string,mixed>>
     */
    public function wire(Restaurant $restaurant, Collection $branches): array
    {
        $stored = ReceiptProfile::query()
            ->whereIn('branch_id', $branches->pluck('id'))
            ->get()
            ->keyBy('branch_id');

        return $branches
            ->sortBy('id')
            ->map(fn (Branch $branch) => $this->row($restaurant, $branch, $stored->get($branch->id)))
            ->values()
            ->all();
    }

    /** @return array<string,mixed> */
    public function row(Restaurant $restaurant, Branch $branch, ?ReceiptProfile $profile): array
    {
        $text = fn (?string $value, string $fallback = '') => filled($value) ? (string) $value : $fallback;

        return [
            'branch_id' => $branch->id,
            // Falls back to the restaurant's name: a slip that says who sold
            // the food is better than one that says nothing, and it is the
            // answer for every restaurant trading under its own brand.
            'trade_name' => $text($profile?->trade_name, (string) ($restaurant->name_en ?: $restaurant->name_ar ?: $restaurant->slug)),
            // The taxpayer's number, authored once on the restaurant. There is
            // no per-branch copy to disagree with it.
            'registration_number' => $text($restaurant->tax_registration_number),
            'activity_code' => $text($profile?->activity_code),
            // ETA's branch code, NOT branches.code (the invoice prefix).
            'branch_code' => $text($profile?->branch_code),
            'country' => $text($profile?->country, 'EG'),
            'governate' => $text($profile?->governate),
            'region_city' => $text($profile?->region_city),
            'street' => $text($profile?->street),
            'building_number' => $text($profile?->building_number),
            'postal_code' => $text($profile?->postal_code),
            'floor' => $text($profile?->floor),
            'room' => $text($profile?->room),
            'landmark' => $text($profile?->landmark),
            'additional_info' => $text($profile?->additional_info),
            'phone' => $text($profile?->phone, (string) ($branch->phone ?? '')),
            'header_note' => $profile?->header_note,
            'footer_note' => $profile?->footer_note,
            'revision' => (int) ($profile?->revision ?? 0),
        ];
    }
}
