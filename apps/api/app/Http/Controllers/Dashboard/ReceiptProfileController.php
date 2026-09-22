<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\UpdateReceiptProfileRequest;
use App\Models\Branch;
use App\Models\ReceiptProfile;
use App\Services\ReceiptProfileService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A3 / CB-08 authoring — the platform is the author of the legal identity on a
 * cloud till's receipt, and the till reads it from the bundle.
 *
 * Shaped after the POS money config (POS-BE-013), which is the template for
 * "platform authors, till reads": RestaurantScope isolates, `{branch}` is route
 * model bound so another tenant's branch is a 404 and not a 403, and the write
 * bumps `pos_config_version` through the PosConfigVersion model hook so the
 * next heartbeat tells every till to re-pull.
 *
 * The read returns a row for EVERY active branch, authored or not, because
 * that is what the bundle carries — the page must show what a till will print,
 * not just what somebody has typed.
 */
class ReceiptProfileController extends Controller
{
    public function __construct(private readonly ReceiptProfileService $profiles) {}

    public function index(Request $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;
        $branches = $restaurant->branches()->where('is_active', true)->orderBy('id')->get();

        return response()->json([
            'data' => [
                // The taxpayer's number lives on the restaurant and is authored
                // there (it is one fact about one taxpayer). Echoed here so the
                // page can show and edit it without a second round trip.
                'registration_number' => (string) ($restaurant->tax_registration_number ?? ''),
                'profiles' => $this->profiles->wire($restaurant, $branches),
            ],
        ]);
    }

    public function update(UpdateReceiptProfileRequest $request, Branch $branch): JsonResponse
    {
        $restaurant = $request->user()->restaurant;
        $data = $request->validated();
        $expected = $data['revision'] ?? null;
        unset($data['revision']);

        $profile = ReceiptProfile::where('branch_id', $branch->id)->first();

        if ($expected !== null && (int) ($profile?->revision ?? 0) !== (int) $expected) {
            // Two managers, an office and a counter. Refusing is the only
            // answer that does not silently discard somebody's typing.
            return response()->json([
                'message' => __('xorder.messages.receipt_profile_stale'),
                'data' => $this->profiles->row($restaurant, $branch, $profile),
            ], 409);
        }

        if ($profile === null) {
            $profile = new ReceiptProfile;
            $profile->branch_id = $branch->id;
        }

        // Empty strings rather than nulls on the text columns: they are NOT
        // NULL with a '' default, matching the till's own table.
        foreach ($data as $key => $value) {
            $data[$key] = in_array($key, ['header_note', 'footer_note'], true)
                ? ($value === '' ? null : $value)
                : (string) ($value ?? '');
        }

        $profile->fill($data);
        $profile->revision = (int) ($profile->revision ?? 0) + 1;
        $profile->updated_by_id = $request->user()->id;
        $profile->save();

        return response()->json([
            'data' => $this->profiles->row($restaurant, $branch, $profile->fresh()),
            'message' => __('xorder.messages.saved'),
        ]);
    }
}
