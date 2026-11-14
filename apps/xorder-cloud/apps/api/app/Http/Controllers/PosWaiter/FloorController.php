<?php

namespace App\Http\Controllers\PosWaiter;

use App\Exceptions\WaiterWireException;
use App\Http\Controllers\Controller;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\WaiterCheckService;
use App\Services\WaiterMenuService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** POS-BE-033 — menu, floor, and one table's check and operations (wire v1). */
class FloorController extends Controller
{
    public function __construct(
        private readonly WaiterCheckService $checks,
        private readonly WaiterMenuService $menu,
    ) {}

    public function menu(Request $request): JsonResponse
    {
        return response()->json($this->menu->menu($this->restaurant($request)));
    }

    public function floor(Request $request): JsonResponse
    {
        return response()->json($this->checks->floor($this->restaurant($request)));
    }

    public function check(Request $request, string $slug, int $table): JsonResponse
    {
        $restaurant = $this->restaurant($request);

        return response()->json($this->checks->check($restaurant, $this->checks->findTable($table)));
    }

    public function ops(Request $request, string $slug, int $table): JsonResponse
    {
        $restaurant = $this->restaurant($request);
        /** @var User $user */
        $user = $request->attributes->get('waiter_user');

        $ops = $request->input('ops');
        $version = $request->input('version');

        if (! is_array($ops) || $ops === [] || count($ops) > 50 || ($version !== null && ! is_int($version))) {
            throw new WaiterWireException('BAD_REQUEST', 400);
        }

        return response()->json($this->checks->apply(
            $restaurant, $user, $this->checks->findTable($table), $version, array_values($ops),
        ));
    }

    private function restaurant(Request $request): Restaurant
    {
        return $request->attributes->get('waiter_restaurant');
    }
}
