<?php

namespace App\Exceptions;

use Exception;
use Illuminate\Http\JsonResponse;

/**
 * An error of the waiter wire (POS-BE-033). The handheld reads `code` and, when
 * present, `reason` and `check` at the TOP level of the body, which is why this
 * is not a PosApiException (that one nests its extras under `details`).
 */
class WaiterWireException extends Exception
{
    /** @param array<string,mixed> $extra top-level members, e.g. ['reason' => …] or ['check' => …] */
    public function __construct(
        public readonly string $errorCode,
        public readonly int $status,
        public readonly array $extra = [],
    ) {
        parent::__construct($errorCode);
    }

    public function render(): JsonResponse
    {
        return response()->json(['code' => $this->errorCode, 'message' => $this->errorCode] + $this->extra, $this->status);
    }
}
