<?php

namespace App\Exceptions;

use Illuminate\Http\JsonResponse;
use RuntimeException;

/**
 * CB-09: a purchasing rule said no. Thrown from inside the service
 * transaction, so nothing already written in that transaction survives
 * (DB::transaction rolls back on any throwable).
 *
 * Renders as {message, code[, errors]}:
 *   409  the order is not in a state that allows this (cancel after a
 *        receipt, send twice, receive against a closed order, a unit clash)
 *   422  the request itself can't be satisfied (send with no lines)
 *
 * `code` is a stable machine string the dashboard can branch on; `message`
 * is translated for the reader.
 */
class PurchasingRefusal extends RuntimeException
{
    /** @param array<string, list<string>> $errors */
    public function __construct(
        public readonly string $refusal,
        string $message,
        public readonly int $status = 409,
        public readonly array $errors = [],
    ) {
        parent::__construct($message);
    }

    public static function conflict(string $code, string $messageKey, array $replace = []): self
    {
        return new self($code, __('xorder.purchasing.'.$messageKey, $replace), 409);
    }

    public static function invalid(string $code, string $messageKey, array $replace = [], ?string $field = null): self
    {
        $message = __('xorder.purchasing.'.$messageKey, $replace);

        return new self($code, $message, 422, $field ? [$field => [$message]] : []);
    }

    public function render(): JsonResponse
    {
        $body = ['message' => $this->getMessage(), 'code' => $this->refusal];
        if ($this->errors !== []) {
            $body['errors'] = $this->errors;
        }

        return response()->json($body, $this->status);
    }
}
