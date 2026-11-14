<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Models\PosTerminal;
use App\Services\PosBootstrapService;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * GET /api/pos/bootstrap (POS-BE-023) — everything this terminal needs, one
 * document. ETag / X-Config-Version are ADVISORY transport sugar; the body's
 * config_version is the client's sole precedence signal (POS-BE-025).
 */
class BootstrapController extends Controller
{
    public function __construct(private readonly PosBootstrapService $bootstrap) {}

    public function show(Request $request): Response
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        $version = (int) $terminal->restaurant->pos_config_version;
        $etag = sprintf('"pos-%d-v%d"', $terminal->restaurant_id, $version);

        if ($request->headers->get('If-None-Match') === $etag) {
            return response('', 304, ['ETag' => $etag, 'X-Config-Version' => (string) $version]);
        }

        return response()
            ->json($this->bootstrap->bundle($terminal))
            ->withHeaders(['ETag' => $etag, 'X-Config-Version' => (string) $version]);
    }
}
