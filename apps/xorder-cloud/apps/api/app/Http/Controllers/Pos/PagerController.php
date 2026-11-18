<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Models\PosTerminal;
use App\Services\PagerSessionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POS-BE-035 (PROPOSED): the till's quick check of a pairing code. The cashier
 * types the code a client read out; this says whether it is open for THIS
 * restaurant, so a typo is caught before the sale rather than after. It is
 * advisory: the till never blocks a sale on it, and the order carries the
 * code either way.
 */
class PagerController extends Controller
{
    public function __construct(private readonly PagerSessionService $pager) {}

    public function peek(Request $request, string $code): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        if (! $this->pager->peek($terminal->restaurant, $code)) {
            return response()->json([
                'code' => 'PAGER_CODE_NOT_FOUND',
                'message' => __('xorder.messages.pager_code_not_found'),
            ], 404);
        }

        return response()->json(['data' => ['open' => true]]);
    }
}
