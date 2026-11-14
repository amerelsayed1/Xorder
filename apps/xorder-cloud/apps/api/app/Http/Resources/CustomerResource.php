<?php

namespace App\Http\Resources;

use App\Models\Customer;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Customer
 */
class CustomerResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'phone' => $this->phone,
            'email' => $this->email,
            'note' => $this->note,
            'orders_count' => $this->whenCounted('orders'),
            'addresses_count' => $this->whenCounted('addresses'),
            'addresses' => $this->whenLoaded('addresses', fn () => $this->addresses->map(fn ($a) => [
                'id' => $a->id,
                'label' => $a->label,
                'address' => $a->address,
                'note' => $a->note,
                'is_default' => $a->is_default,
            ])),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
