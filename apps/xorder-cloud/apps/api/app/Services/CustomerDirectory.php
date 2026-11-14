<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\CustomerAddress;
use App\Rules\MobileNumber;
use Illuminate\Support\Facades\Log;

/**
 * Upserts a restaurant's directory customer (keyed by normalized phone) and,
 * when supplied, remembers their address. Shared by the guest order pipeline
 * and the WhatsApp checkout (which saves the customer but records no order).
 *
 * Callers must have pinned the tenant (TenantContext::overrideId) first — the
 * customer/address models are tenant-scoped and stamped from that context.
 * Best-effort: a hiccup here must never block checkout.
 */
class CustomerDirectory
{
    /**
     * @param  array<string,mixed>  $data  customer_phone/name/email/address/address_label
     * @return array{0: ?Customer, 1: ?CustomerAddress}
     */
    public function upsert(array $data): array
    {
        // Normalize Arabic/Persian digits so the directory keys on one canonical
        // form (the unique index is on restaurant_id + phone).
        $phone = MobileNumber::normalizeDigits((string) ($data['customer_phone'] ?? ''));
        if ($phone === '') {
            return [null, null];
        }

        try {
            $customer = Customer::firstOrNew(['phone' => $phone]);
            if (! empty($data['customer_name'])) {
                $customer->name = $data['customer_name'];
            }
            if (! empty($data['customer_email'])) {
                $customer->email = $data['customer_email'];
            }
            $customer->save();

            $address = null;
            $text = trim((string) ($data['customer_address'] ?? ''));
            if ($text !== '') {
                $address = $customer->addresses()->where('address', $text)->first();
                if ($address === null) {
                    $address = $customer->addresses()->create([
                        'label' => $data['address_label'] ?? null,
                        'address' => $text,
                        'is_default' => $customer->addresses()->count() === 0,
                    ]);
                }
            }

            return [$customer, $address];
        } catch (\Throwable $e) {
            Log::warning('Customer upsert failed', ['error' => $e->getMessage()]);

            return [null, null];
        }
    }
}
