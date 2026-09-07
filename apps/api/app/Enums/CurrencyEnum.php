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

    /**
     * The IANA timezone a restaurant billing in this currency almost certainly
     * keeps its day by, or null when the currency spans too many zones to guess
     * (USD, EUR, GBP).
     *
     * Only ever a *starting* value: it seeds the timezone of a newly created
     * restaurant and backfilled the ones that predate the setting. The owner can
     * change it in their profile, and that choice is what everything reads. This
     * exists because the alternative default — UTC — silently rolls "today" over
     * at 2 or 3am local, so a Cairo owner watching the dashboard just after
     * midnight still sees yesterday's numbers.
     */
    public function defaultTimezone(): ?string
    {
        return match ($this) {
            self::EGP => 'Africa/Cairo',
            self::SAR => 'Asia/Riyadh',
            self::AED => 'Asia/Dubai',
            self::KWD => 'Asia/Kuwait',
            self::QAR => 'Asia/Qatar',
            self::BHD => 'Asia/Bahrain',
            self::OMR => 'Asia/Muscat',
            self::JOD => 'Asia/Amman',
            self::USD, self::EUR, self::GBP => null,
        };
    }

    /**
     * Minor-unit exponent (ISO 4217). The reason POS money is integer minor
     * units in the first place: KWD/BHD/OMR/JOD are three-decimal currencies
     * that decimal(10,2) cannot represent (D1). Hardcoding 100 anywhere is a
     * bug for a Kuwaiti tenant — divide/multiply by 10 ** exponent().
     */
    public function exponent(): int
    {
        return match ($this) {
            self::KWD, self::BHD, self::OMR, self::JOD => 3,
            default => 2,
        };
    }
}
