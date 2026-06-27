<?php

namespace App\Http\Controllers;

use App\Services\ImageUploadService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class UploadController extends Controller
{
    public function store(Request $request, ImageUploadService $uploads): JsonResponse
    {
        $maxKb = (int) config('platform.uploads.max_kb', 4096);
        $mimes = implode(',', config('platform.uploads.mimes', ['jpg', 'jpeg', 'png', 'webp']));

        $request->validate([
            'image' => ['required', 'image', "mimes:{$mimes}", "max:{$maxKb}"],
            'folder' => ['nullable', 'string', 'in:logos,covers,categories,items,uploads'],
        ]);

        $url = $uploads->store($request->file('image'), $request->input('folder', 'uploads'));

        return response()->json([
            'data' => ['url' => $url],
            'message' => 'Image uploaded.',
        ], 201);
    }
}
