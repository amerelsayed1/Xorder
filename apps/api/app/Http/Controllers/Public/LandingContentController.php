<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\LandingContent;
use Illuminate\Http\JsonResponse;

class LandingContentController extends Controller
{
    /**
     * Public landing page content consumed by the standalone landing app.
     */
    public function show(): JsonResponse
    {
        return response()->json([
            'data' => LandingContent::current()->content,
        ]);
    }
}
