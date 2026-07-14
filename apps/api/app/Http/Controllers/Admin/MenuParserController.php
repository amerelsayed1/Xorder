<?php

namespace App\Http\Controllers\Admin;

use Anthropic\Anthropic;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MenuParserController extends Controller
{
    public function parse(Request $request): JsonResponse
    {
        $request->validate([
            'image' => 'required|image|mimes:jpeg,png,jpg,gif|max:10240',
        ]);

        $apiKey = config('services.anthropic.api_key') ?? env('ANTHROPIC_API_KEY');

        if (! $apiKey) {
            return response()->json([
                'error' => 'Anthropic API key is not configured',
            ], 500);
        }

        $file = $request->file('image');
        $imageData = base64_encode(file_get_contents($file->getRealPath()));
        $mimeType = $file->getMimeType();

        $client = new Anthropic(['apiKey' => $apiKey]);

        try {
            $response = $client->messages()->create([
                'model' => 'claude-3-5-sonnet-20241022',
                'max_tokens' => 2048,
                'messages' => [
                    [
                        'role' => 'user',
                        'content' => [
                            [
                                'type' => 'image',
                                'source' => [
                                    'type' => 'base64',
                                    'media_type' => $mimeType,
                                    'data' => $imageData,
                                ],
                            ],
                            [
                                'type' => 'text',
                                'text' => 'Extract all menu items from this image. For each item, provide: name, price (as a number), and description (if available). Return as a JSON array with objects containing these fields: {"name": "string", "price": number, "description": "string"}. Return ONLY the JSON array, no other text.',
                            ],
                        ],
                    ],
                ],
            ]);

            $content = $response->content[0]->text;

            // Clean up the response text (remove markdown code blocks if present)
            $content = preg_replace('/^```json\n?|\n?```$/', '', trim($content));
            $content = preg_replace('/^```\n?|\n?```$/', '', trim($content));

            $items = json_decode($content, true);

            if (! is_array($items)) {
                return response()->json([
                    'error' => 'Failed to parse menu items from image',
                    'raw_response' => $content,
                ], 422);
            }

            return response()->json([
                'data' => $items,
                'message' => 'Menu items extracted successfully',
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to parse menu: '.$e->getMessage(),
            ], 500);
        }
    }
}
