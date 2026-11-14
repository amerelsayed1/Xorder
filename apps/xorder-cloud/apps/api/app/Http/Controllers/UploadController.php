<?php

namespace App\Http\Controllers;

use App\Exceptions\UnprocessableImage;
use App\Services\ImageUploadService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class UploadController extends Controller
{
    public function store(Request $request, ImageUploadService $uploads): JsonResponse
    {
        $maxKb = (int) config('platform.uploads.max_kb', 4096);
        $mimes = implode(',', config('platform.uploads.mimes', ['jpg', 'jpeg', 'png', 'webp']));

        $request->validate([
            // `file` + `mimes` (not the strict `image` rule) so modern formats
            // like avif are accepted; the mimes list still restricts to images.
            //
            // `mimes` matches on the SNIFFED content type, not the filename, so
            // shell.php renamed to shell.jpg — or an SVG carrying <script> —
            // fails here rather than reaching the decoder.
            'image' => ['required', 'file', "mimes:{$mimes}", "max:{$maxKb}"],
            'folder' => ['nullable', 'string', 'in:logos,covers,categories,items,uploads'],
        ]);

        try {
            $url = $uploads->store($request->file('image'), $request->input('folder', 'uploads'));
        } catch (UnprocessableImage $e) {
            // A file that sniffs as an image but will not decode (truncated, a
            // polyglot whose image half is corrupt, a decompression bomb) is bad
            // input, not a server fault — 422 with a message the UI can show,
            // rather than a 500 and a stack trace in the log.
            throw ValidationException::withMessages(['image' => $e->getMessage()]);
        }

        return response()->json([
            'data' => ['url' => $url],
            'message' => __('xorder.messages.image_uploaded'),
        ], 201);
    }
}
