<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Resources\AuditLogResource;
use App\Models\AuditLog;
use App\Models\Restaurant;
use App\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Super-admin audit trail. Read-only: rows are written by
 * {@see AuditLogger}, never through the API.
 */
class AuditLogController extends Controller
{
    /** Paginated, newest-first log — filterable by tenant, client (actor), category, action, and date. */
    public function index(Request $request): JsonResponse
    {
        $perPage = min((int) $request->integer('per_page', 30) ?: 30, 100);

        $logs = AuditLog::query()
            ->with(['restaurant', 'actor'])
            // Tenant filter.
            ->when($request->filled('restaurant_id'), fn ($q) => $q->where('restaurant_id', $request->integer('restaurant_id')))
            // Client / actor filter.
            ->when($request->filled('actor_id'), fn ($q) => $q->where('actor_id', $request->integer('actor_id')))
            ->when($request->filled('actor_role'), fn ($q) => $q->where('actor_role', $request->string('actor_role')))
            // Category (action prefix, e.g. "auth") or exact action.
            ->when($request->filled('category'), fn ($q) => $q->where('action', 'like', $request->string('category').'.%'))
            ->when($request->filled('action'), fn ($q) => $q->where('action', $request->string('action')))
            // Free-text over the human description.
            ->when($request->filled('search'), fn ($q) => $q->where('description', 'like', '%'.$request->string('search').'%'))
            // Date range (inclusive) on when it happened.
            ->when($request->filled('from'), fn ($q) => $q->whereDate('created_at', '>=', $request->date('from')))
            ->when($request->filled('to'), fn ($q) => $q->whereDate('created_at', '<=', $request->date('to')))
            ->latest()
            ->paginate($perPage)
            ->withQueryString();

        return AuditLogResource::collection($logs)->response();
    }

    /** Options for the filter controls: tenants, actors, and the action taxonomy actually present. */
    public function filters(): JsonResponse
    {
        $actions = AuditLog::query()
            ->select('action')
            ->distinct()
            ->orderBy('action')
            ->pluck('action');

        $categories = $actions
            ->map(fn ($a) => str_contains($a, '.') ? strtok($a, '.') : $a)
            ->unique()
            ->values();

        // Distinct actors that appear in the log (so the dropdown only lists
        // people who actually did something).
        $actors = AuditLog::query()
            ->whereNotNull('actor_id')
            ->select('actor_id', 'actor_name', 'actor_role')
            ->distinct()
            ->orderBy('actor_name')
            ->get()
            ->map(fn ($r) => [
                'id' => $r->actor_id,
                'name' => $r->actor_name,
                'role' => $r->actor_role,
            ])
            ->values();

        $tenants = Restaurant::query()
            ->orderBy('name_en')
            ->get(['id', 'name_en', 'name_ar', 'slug'])
            ->map(fn ($r) => [
                'id' => $r->id,
                'name' => $r->name_en ?: ($r->name_ar ?: $r->slug),
            ]);

        return response()->json([
            'data' => [
                'tenants' => $tenants,
                'actors' => $actors,
                'actions' => $actions,
                'categories' => $categories,
            ],
        ]);
    }
}
