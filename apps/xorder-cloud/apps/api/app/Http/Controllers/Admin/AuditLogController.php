<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Restaurant;
use App\Services\ActivityLogReader;
use App\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * Super-admin activity trail. Read-only, and read from the daily activity
 * files written by {@see AuditLogger} — there is no audit table behind this.
 * The response shape is unchanged from when there was one, so the SPA is
 * unaffected by where the rows come from.
 */
class AuditLogController extends Controller
{
    public function __construct(private readonly ActivityLogReader $reader) {}

    /** Paginated, newest-first — filterable by tenant, actor, category, action, date and free text. */
    public function index(Request $request): JsonResponse
    {
        $perPage = min((int) $request->integer('per_page', 30) ?: 30, 100);

        $page = $this->reader->paginate(
            $request->only(['restaurant_id', 'actor_id', 'actor_role', 'category', 'action', 'search', 'from', 'to']),
            (int) $request->integer('page', 1),
            $perPage,
        );

        return response()->json($page);
    }

    /**
     * The day files on disk — the trail is stored as one file per day, so the
     * screens list them. `restaurant_id` scopes the per-file event counts, so a
     * tenant's page reports that tenant's events rather than the platform's.
     */
    public function files(Request $request): JsonResponse
    {
        return response()->json([
            'data' => $this->reader->inventory($request->only(['restaurant_id'])),
        ]);
    }

    /**
     * Download one day's file. Unfiltered it streams the file as stored; with
     * `restaurant_id` it streams only that tenant's lines, so a download taken
     * from a tenant's page does not carry every other tenant that shared the
     * day. `$date` is matched against the known set of day files rather than
     * interpolated into a path — it arrives from the URL.
     */
    public function download(Request $request, string $date): Response
    {
        $filters = $request->only(['restaurant_id']);
        $body = $this->reader->rawLinesFor($date, $filters);

        abort_if($body === null, 404);

        $name = 'activity-'.$date.($filters === [] ? '' : '-filtered').'.log';

        return response($body, 200, [
            'Content-Type' => 'application/x-ndjson',
            'Content-Disposition' => 'attachment; filename='.$name,
        ]);
    }

    /** Options for the filter controls: tenants, plus the actors and actions actually present in the files. */
    public function filters(): JsonResponse
    {
        $options = $this->reader->options();

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
                'actors' => $options['actors'],
                'actions' => $options['actions'],
                'categories' => $options['categories'],
            ],
        ]);
    }
}
