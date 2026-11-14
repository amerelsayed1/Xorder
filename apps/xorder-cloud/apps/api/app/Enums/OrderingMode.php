<?php

namespace App\Enums;

/**
 * How a restaurant takes orders from the public menu. A restaurant picks exactly
 * one channel — the two are mutually exclusive, never combined.
 *  - WHATSAPP: checkout opens a pre-filled WhatsApp message; no order record.
 *  - SYSTEM:   checkout submits an order into the dashboard Orders board; no WhatsApp.
 */
enum OrderingMode: string
{
    case WHATSAPP = 'whatsapp';
    case SYSTEM = 'system';

    /** Does this mode open a WhatsApp handoff at checkout? */
    public function usesWhatsapp(): bool
    {
        return $this === self::WHATSAPP;
    }

    /** Does this mode persist an order record in the system? */
    public function usesSystem(): bool
    {
        return $this === self::SYSTEM;
    }
}
