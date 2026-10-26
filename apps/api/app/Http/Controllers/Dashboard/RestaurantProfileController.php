<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\UpdateRestaurantProfileRequest;
use App\Http\Resources\RestaurantResource;
use App\Services\PosConfigVersion;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RestaurantProfileController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        return response()->json([
            'data' => RestaurantResource::make($request->user()->restaurant->loadMissing('features')),
        ]);
    }

    public function update(UpdateRestaurantProfileRequest $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;
        $data = $request->validated();

        // A3: the tax registration number rides the POS bootstrap bundle, both
        // as `restaurant.tax_registration_number` and as every receipt
        // profile's `registration_number`. Changing it must therefore tell the
        // tills — bumped explicitly rather than by hooking Restaurant, because
        // a new cover image is not a bundle change (PosConfigVersion).
        $trnChanged = array_key_exists('tax_registration_number', $data)
            && (string) $data['tax_registration_number'] !== (string) $restaurant->tax_registration_number;

        // Content languages ride the POS bundle (restaurant.default_language and
        // bilingual), so a change must tell the tills too.
        $languagesChanged = (array_key_exists('default_language', $data)
                && (string) $data['default_language'] !== (string) $restaurant->default_language?->value)
            || (array_key_exists('bilingual', $data)
                && (bool) $data['bilingual'] !== ($restaurant->bilingual !== false));

        $restaurant->update($data);

        if ($trnChanged || $languagesChanged) {
            PosConfigVersion::bump($restaurant);
        }

        return response()->json([
            'data' => RestaurantResource::make($restaurant->fresh()),
            'message' => __('xorder.messages.profile_updated'),
        ]);
    }
}
