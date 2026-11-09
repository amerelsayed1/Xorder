<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Http\Requests\Pos\AcceptOnlineOrderRequest;
use App\Http\Requests\Pos\HandleTableRequestRequest;
use App\Http\Requests\Pos\RejectOnlineOrderRequest;
use App\Http\Resources\Pos\IncomingEventResource;
use App\Models\PosTerminal;
use App\Services\OnlineOrderInbox;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POS-BE-033 — the till's feed of online orders and table requests, and the
 * three things it can do with them. Thin: scope, locking and idempotency live
 * in OnlineOrderInbox.
 */
class PosIncomingController extends Controller
{
    public function __construct(private readonly OnlineOrderInbox $inbox) {}

    public function index(Request $request): JsonResponse
    {
        $request->validate(['cursor' => ['nullable', 'string', 'max:2000']]);

        $result = $this->inbox->feed(
            $this->terminal($request),
            $request->query('cursor'),
            $request->header('X-App-Version') ?: $request->query('app_version'),
        );

        $response = response()->json(['data' => [
            'events' => IncomingEventResource::collection($result['events'])->resolve(),
            'cursor' => $result['cursor'],
            'has_more' => $result['has_more'],
        ]]);

        // Same ETag/304 pattern as the dashboard pulse: an idle poll is a bare header round-trip.
        $response->setEtag(md5((string) $response->getContent()));
        $response->isNotModified($request);

        return $response;
    }

    public function accept(AcceptOnlineOrderRequest $request, int $order): JsonResponse
    {
        $o = $this->inbox->accept($this->terminal($request), $order, $request->validated()['client_request_id']);

        return response()->json(['data' => (new IncomingEventResource(['kind' => 'online_order', 'model' => $o]))->resolve()]);
    }

    public function reject(RejectOnlineOrderRequest $request, int $order): JsonResponse
    {
        $v = $request->validated();
        $o = $this->inbox->reject($this->terminal($request), $order, $v['client_request_id'], $v['reason']);

        return response()->json(['data' => (new IncomingEventResource(['kind' => 'online_order', 'model' => $o]))->resolve()]);
    }

    public function handled(HandleTableRequestRequest $request, int $billRequest): JsonResponse
    {
        $r = $this->inbox->handled($this->terminal($request), $billRequest, $request->validated()['client_request_id']);

        return response()->json(['data' => (new IncomingEventResource(['kind' => 'table_request', 'model' => $r]))->resolve()]);
    }

    private function terminal(Request $request): PosTerminal
    {
        return $request->attributes->get('pos_terminal');
    }
}
