<?php

namespace App\Http\Controllers\Public;

use App\Enums\LeadStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Public\StoreLeadRequest;
use App\Models\Lead;
use Illuminate\Http\JsonResponse;

class LeadController extends Controller
{
    /**
     * Capture a "request a demo" lead submitted from the public landing page.
     * Returns no lead data — this endpoint is unauthenticated.
     */
    public function store(StoreLeadRequest $request): JsonResponse
    {
        // Honeypot: the landing form ships a visually-hidden "website" field
        // humans never fill. Bots that fill it get the normal success response
        // (so they can't tell they were caught) but no lead is stored.
        if (! $request->filled('website')) {
            Lead::create($request->validated() + ['status' => LeadStatus::NEW->value]);
        }

        return response()->json([
            'message' => __('xorder.messages.lead_received'),
        ], 201);
    }
}
