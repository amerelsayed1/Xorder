<?php

namespace App\Enums;

enum CurrencyEnum: string
{
    case EGP = 'EGP';
    case SAR = 'SAR';
    case AED = 'AED';
    case USD = 'USD';
    case KWD = 'KWD';
    case QAR = 'QAR';
    case BHD = 'BHD';
    case OMR = 'OMR';
    case JOD = 'JOD';
    case EUR = 'EUR';
    case GBP = 'GBP';

    /** Short display token shown next to prices. */
    public function symbol(): string
    {
        return match ($this) {
            self::EGP => 'EGP',
            self::SAR => 'SR',
            self::AED => 'AED',
            self::USD => '$',
            self::KWD => 'KD',
            self::QAR => 'QR',
            self::BHD => 'BD',
            self::OMR => 'OMR',
            self::JOD => 'JD',
            self::EUR => '€',
            self::GBP => '£',
        };
    }
}
