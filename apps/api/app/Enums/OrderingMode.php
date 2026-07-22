<?php

namespace App\Enums;

/**
 * How a restaurant takes orders from the public menu.
 *  - WHATSAPP: checkout opens a pre-filled WhatsApp message; no order record.
 *  - SYSTEM:   checkout submits an order into the dashboard Orders board; no WhatsApp.
 *  - BOTH:     record the order AND open WhatsApp (the historical behaviour).
 */
enum OrderingMode: string
{
    case WHATSAPP = 'whatsapp';
    case SYSTEM = 'system';
    case BOTH = 'both';

    /** Does this mode open a WhatsApp handoff at checkout? */
    public function usesWhatsapp(): bool
    {
        return $this !== self::SYSTEM;
    }

    /** Does this mode persist an order record in the system? */
    public function usesSystem(): bool
    {
        return $this !== self::WHATSAPP;
    }
}
