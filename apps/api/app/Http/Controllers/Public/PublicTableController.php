<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\DiningTable;
use App\Models\MenuSession;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Public entry point for a table QR scan. Resolves the opaque token to its
 * restaurant/branch/area/table (never exposing the internal id) and opens a
 * table-bound menu session.
 */
class PublicTableController extends Controller
{
    /** GET /public/tables/{token} — table context for the menu banner. */
    public function show(string $token): JsonResponse
    {
        return response()->json(['data' => $this->context($this->resolve($token))]);
    }

    /** POST /public/tables/{token}/sessions — start a table menu session. */
    public function createSession(Request $request, string $token): JsonResponse
    {
        $request->validate(['language' => ['nullable', 'in:ar,en']]);

        $table = $this->resolve($token);
        $ttl = (int) config('platform.table_session_ttl_minutes', 240);

        $session = new MenuSession([
            'branch_id' => $table->branch_id,
            'dining_area_id' => $table->dining_area_id,
            'table_id' => $table->id,
            'language' => $request->input('language') ?? $table->restaurant->default_language->value,
            'session_token' => Str::random(40),
            'started_at' => now(),
            'last_activity_at' => now(),
            'expires_at' => now()->addMinutes($ttl),
        ]);
        $session->restaurant_id = $table->restaurant_id;
        $session->save();

        return response()->json([
            'data' => $this->context($table) + [
                'session_token' => $session->session_token,
                'expires_at' => $session->expires_at,
            ],
        ], 201);
    }

    /**
     * Look up the table and enforce the scan-time guards (FR-SESSION-006/007/008).
     */
    private function resolve(string $token): DiningTable
    {
        $table = DiningTable::withoutGlobalScopes()
            ->with(['restaurant', 'branch', 'diningArea'])
            ->where('public_token', $token)
            ->first();

        if ($table === null) {
            abort(404, __('xorder.messages.table_qr_invalid'));
        }
        if (! $table->restaurant->isPubliclyVisible()) {
            abort(403, __('xorder.messages.menu_unavailable'));
        }
        if (! $table->is_active) {
            abort(403, __('xorder.messages.table_disabled'));
        }
        if ($table->branch && ! $table->branch->is_active) {
            abort(403, __('xorder.messages.branch_disabled'));
        }

        return $table;
    }

    /** @return array<string,mixed> */
    private function context(DiningTable $table): array
    {
        $r = $table->restaurant;

        return [
            'restaurant' => [
                'slug' => $r->slug,
                'name_ar' => $r->name_ar,
                'name_en' => $r->name_en,
                'default_language' => $r->default_language->value,
                'bilingual' => $r->bilingual,
            ],
            'branch' => $table->branch ? ['name_ar' => $table->branch->name_ar, 'name_en' => $table->branch->name_en] : null,
            'area' => $table->diningArea ? ['name_ar' => $table->diningArea->name_ar, 'name_en' => $table->diningArea->name_en] : null,
            'table' => ['label' => $table->label],
            'order_type' => 'dine_in',
        ];
    }
}
