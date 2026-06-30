<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateLandingContentRequest;
use App\Models\LandingContent;
use Illuminate\Http\JsonResponse;

class LandingContentController extends Controller
{
    public function show(): JsonResponse
    {
        return response()->json([
            'data' => LandingContent::current()->content,
        ]);
    }

    public function update(UpdateLandingContentRequest $request): JsonResponse
    {
        $landing = LandingContent::current();
        $landing->update(['content' => $request->validated()['content']]);

        return response()->json([
            'data' => $landing->fresh()->content,
            'message' => __('xorder.messages.landing_updated'),
        ]);
    }
}
