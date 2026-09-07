<?php

namespace App\Exceptions;

use Exception;
use Illuminate\Http\JsonResponse;

/**
 * A POS-BE-019 error: every 4xx from /api/pos/* carries a stable
 * {"code": "SNAKE_CASE", "message": "...", "details": {}?} envelope, because
 * the client's reaction differs completely by cause and an HTTP status alone
 * cannot distinguish "hold and retry" from "stop and tell the manager" from
 * "quarantine this one record". The client switches on `code` and retries
 * anything it does not recognise — so ADDING a code is never breaking.
 *
 * Rendered in bootstrap/app.php. Services throw; controllers stay thin.
 */
class PosApiException extends Exception
{
    /** @param array<string,mixed>|null $details */
    public function __construct(
        public readonly string $errorCode,
        public readonly int $status,
        public readonly ?array $details = null,
        ?string $message = null,
    ) {
        parent::__construct($message ?? self::defaultMessage($errorCode));
    }

    public function render(): JsonResponse
    {
        $body = ['code' => $this->errorCode, 'message' => $this->getMessage()];

        if ($this->details !== null) {
            $body['details'] = $this->details;
        }

        return response()->json($body, $this->status);
    }

    /**
     * Operator-facing message per code, via lang so the AR dashboard reads
     * naturally. Falls back to the code itself — a till switches on `code`, so
     * a missing translation degrades cosmetically, never behaviourally.
     */
    private static function defaultMessage(string $code): string
    {
        $key = 'xorder.pos.'.$code;
        $message = __($key);

        return $message === $key ? $code : $message;
    }
}
