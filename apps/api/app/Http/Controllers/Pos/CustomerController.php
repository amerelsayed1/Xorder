<?php

namespace App\Http\Controllers\Pos;

use App\Enums\TenantCapability;
use App\Http\Controllers\Controller;
use App\Http\Requests\Pos\StorePosCustomerRequest;
use App\Models\PosTerminal;
use App\Services\PosCustomerService;
use Illuminate\Http\JsonResponse;

/**
 * POS-BE-014 — a customer created from the till.
 *
 * Contract agreed 2026-09-02, built 2026-09-27 on the owner's go. A delivery
 * order needs a customer with an address (POS-R072) and a cashier taking a
 * phone order had no way to make one: customers could only be created on the
 * public, unauthenticated diner path.
 *
 * **One directory, not two.** This goes through `CustomerDirectory::upsert()`
 * — the same call the diner path makes — so a regular who has ordered from
 * their phone and then gives the same number at the counter is one customer
 * and not two. The contract asked for that in as many words, because phone
 * normalisation that differs by a single rule splits the directory silently.
 */
class CustomerController extends Controller
{
    public function __construct(private readonly PosCustomerService $service) {}

    public function store(StorePosCustomerRequest $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        ['customer' => $customer, 'replay' => $replay] =
            $this->service->create($terminal, $request->validated());

        return response()->json([
            'data' => [
                'id' => $customer->id,
                'client_transaction_id' => $request->validated()['client_transaction_id'],
                'name' => $customer->name,
                'phone' => $customer->phone,
                'email' => $customer->email,
                'address' => $customer->addresses()->value('address'),
            ],
        ], $replay ? 200 : 201);
    }

    /** The verb this endpoint needs, named once. */
    public const CAPABILITY = TenantCapability::CUSTOMERS_CREATE;
}
