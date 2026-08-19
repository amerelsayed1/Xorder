<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class OrderRoundResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'sequence' => $this->sequence,
            'items' => $this->items->map(fn ($item) => [
                'id' => $item->id,
                'name' => $item->name,
                'qty' => $item->quantity,
                'options' => $item->options ?? [],
                'note' => $item->note,
                'unit_price' => $item->unit_price,
                'line_total' => $item->line_total,
            ]),
            'total' => $this->total,
            'note' => $this->note,
            'submitted_at' => $this->submitted_at?->toIso8601String(),
        ];
    }
}
