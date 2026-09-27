<?php

namespace App\Services;

use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Exceptions\PosApiException;
use App\Models\Customer;
use App\Models\PosTerminal;
use App\Models\User;
use App\Rules\MobileNumber;
use App\Support\TenantContext;

/**
 * POS-BE-014 — creating a customer from a till.
 *
 * Thin on purpose. Everything that decides what a customer IS lives in
 * {@see CustomerDirectory::upsert()}, which the diner path also calls; this
 * class only does the three things that are the till's own: pin the tenant
 * the device token names, check the cashier may do it, and make a replay
 * harmless.
 */
class PosCustomerService
{
    public function __construct(private readonly CustomerDirectory $directory) {}

    /**
     * @param  array<string,mixed>  $data
     * @return array{customer: Customer, replay: bool}
     */
    public function create(PosTerminal $terminal, array $data): array
    {
        $this->assertActorMay($terminal, $data['acting_user_id'] ?? null);

        // The device token names the tenant; the payload never does. Pinned
        // the same way the public path pins it, because `upsert()` reads the
        // tenant from context rather than taking it as an argument.
        TenantContext::overrideId($terminal->restaurant_id);

        try {
            $phone = MobileNumber::normalizeDigits((string) $data['phone']);

            // **Replay is a lookup, not a second write.** POS-BE-007 requires
            // a repeated request to answer the same way; here the natural key
            // does the work, because a customer is identified by phone within
            // a restaurant. A till that lost the reply re-sends and gets the
            // same customer back with 200 rather than 201 — and an upsert
            // makes that true even for the first caller.
            $existing = Customer::where('phone', $phone)->first();

            [$customer, ] = $this->directory->upsert([
                'customer_name' => $data['name'],
                'customer_phone' => $data['phone'],
                'customer_email' => $data['email'] ?? null,
                'customer_address' => $data['address'] ?? null,
                'address_label' => $data['address_label'] ?? null,
            ]);

            if ($customer === null) {
                // `upsert()` answers null for an unusable phone and for a
                // write it could not make. Neither is something the till can
                // fix by sending again, and a 500 would have it retry forever.
                throw new PosApiException('VALIDATION_FAILED', 422, [
                    'errors' => ['phone' => ['This phone number cannot be saved.']],
                ]);
            }

            return ['customer' => $customer, 'replay' => $existing !== null];
        } finally {
            TenantContext::clearOverride();
        }
    }

    /**
     * The cashier, when one is named.
     *
     * Null is accepted for the same reason it is on an order (the v1
     * relaxation): a till that could not name whoever is standing there still
     * has to be able to take the order. When a user IS named they must exist,
     * belong to this tenant, be active, and hold the verb.
     */
    private function assertActorMay(PosTerminal $terminal, ?int $userId): void
    {
        if ($userId === null) {
            return;
        }

        $user = User::where('restaurant_id', $terminal->restaurant_id)
            ->where('status', UserStatus::ACTIVE)
            ->find($userId);

        if ($user === null || ! $user->isTenantUser()) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['acting_user_id' => ['Unknown user.']],
            ]);
        }

        if (! $user->holdsTenantCapability(TenantCapability::CUSTOMERS_CREATE)) {
            throw new PosApiException('POS_CAPABILITY_MISSING', 403, [
                'capability' => TenantCapability::CUSTOMERS_CREATE->value,
            ]);
        }
    }
}
