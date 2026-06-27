<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Services\PublicMenuService;
use Illuminate\Contracts\View\View;
use Illuminate\Http\Response;

class PublicMenuController extends Controller
{
    public function __construct(private readonly PublicMenuService $menu)
    {
    }

    /** Server-rendered public menu at /r/{slug}. */
    public function show(string $slug): View|Response
    {
        $restaurant = $this->menu->findBySlug($slug);

        if ($restaurant === null) {
            return response()->view('public.unavailable', [
                'restaurant' => null,
            ], 404);
        }

        if (! $this->menu->isVisible($restaurant)) {
            // 200 (not 404): the slug is valid, the menu is just temporarily off.
            return response()->view('public.unavailable', [
                'restaurant' => $restaurant,
            ], 200);
        }

        $data = $this->menu->loadMenu($restaurant);

        return view('public.menu', [
            'restaurant' => $restaurant,
            'categories' => $data['categories'],
            'featured' => $data['featured'],
        ]);
    }
}
