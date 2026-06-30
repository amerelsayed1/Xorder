<?php

namespace App\Http\Controllers\Admin;

use App\Enums\LeadStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateLeadRequest;
use App\Http\Resources\LeadResource;
use App\Models\Lead;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;

class LeadController extends Controller
{
    /**
     * Lead inbox with optional status filter + free-text search.
     * Returns the most recent leads plus per-status counts for the filter chips.
     */
    public function index(Request $request): JsonResponse
    {
        $status = $request->string('status')->toString();
        $search = trim($request->string('q')->toString());

        $leads = Lead::query()
            ->when($status !== '' && in_array($status, LeadStatus::values(), true),
                fn ($q) => $q->where('status', $status))
            ->when($search !== '', function ($q) use ($search) {
                $like = '%'.$search.'%';
                $q->where(function ($w) use ($like) {
                    $w->where('restaurant_name', 'like', $like)
                        ->orWhere('contact_name', 'like', $like)
                        ->orWhere('whatsapp', 'like', $like)
                        ->orWhere('city', 'like', $like);
                });
            })
            ->latest()
            ->limit(500)
            ->get();

        $counts = Lead::query()
            ->selectRaw('status, count(*) as aggregate')
            ->groupBy('status')
            ->pluck('aggregate', 'status');

        return response()->json([
            'data' => LeadResource::collection($leads),
            'meta' => [
                'counts' => $counts,
                'total' => Lead::count(),
            ],
        ]);
    }

    public function update(UpdateLeadRequest $request, Lead $lead): JsonResponse
    {
        $lead->update($request->validated());

        return response()->json([
            'data' => LeadResource::make($lead->fresh()),
            'message' => __('xorder.messages.lead_updated'),
        ]);
    }

    /** Stream every lead as a CSV download. */
    public function export(): StreamedResponse
    {
        $headers = ['Content-Type' => 'text/csv; charset=UTF-8'];

        return response()->streamDownload(function () {
            $out = fopen('php://output', 'w');
            // UTF-8 BOM so Excel renders Arabic correctly.
            fwrite($out, "\xEF\xBB\xBF");
            fputcsv($out, [
                'ID', 'Restaurant', 'Contact', 'WhatsApp', 'City',
                'Business type', 'Message', 'Source', 'Status', 'Created',
            ]);

            Lead::query()->latest()->chunk(200, function ($chunk) use ($out) {
                foreach ($chunk as $lead) {
                    fputcsv($out, [
                        $lead->id,
                        $lead->restaurant_name,
                        $lead->contact_name,
                        $lead->whatsapp,
                        $lead->city,
                        $lead->business_type,
                        $lead->message,
                        $lead->source,
                        $lead->status->value,
                        $lead->created_at?->toDateTimeString(),
                    ]);
                }
            });

            fclose($out);
        }, 'leads.csv', $headers);
    }
}
