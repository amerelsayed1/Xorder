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
    /**
     * @param  array<string, list<string>>  $errors
     * @param  array<string, mixed>  $details  machine-readable figures (slice c: the room left
     *                                         on an invoice), rendered as `details`
     */
    public function __construct(
        public readonly string $refusal,
        string $message,
        public readonly int $status = 409,
        public readonly array $errors = [],
        public readonly array $details = [],
    ) {
        parent::__construct($message);
    }

    public static function conflict(string $code, string $messageKey, array $replace = [], ?string $field = null, array $details = []): self
    {
        $message = __('xorder.purchasing.'.$messageKey, $replace);

        return new self($code, $message, 409, $field ? [$field => [$message]] : [], $details);
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
        if ($this->details !== []) {
            $body['details'] = $this->details;
        }

        return response()->json($body, $this->status);
    }
}
