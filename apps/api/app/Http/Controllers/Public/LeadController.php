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
        Lead::create($request->validated() + ['status' => LeadStatus::NEW->value]);

        return response()->json([
            'message' => __('xorder.messages.lead_received'),
        ], 201);
    }
}
