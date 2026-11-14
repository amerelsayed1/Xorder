<?php

namespace App\Support;

/**
 * Neutralises spreadsheet formula injection (CWE-1236). Cells whose value
 * begins with =, +, -, @, or a leading tab/CR are treated as formulas by
 * Excel/LibreOffice/Google Sheets and can execute DDE/HYPERLINK payloads when
 * the export is opened. Since much of XOrder's exported text originates from
 * unauthenticated public input (order item names, lead form fields), every
 * outbound cell is defused before it reaches the writer.
 */
class CsvSafe
{
    /** Prefix a risky leading character with a single quote so it stays text. */
    public static function cell(mixed $value): mixed
    {
        if (! is_string($value) || $value === '') {
            return $value;
        }

        if (preg_match('/^[=+\-@\t\r]/', $value) === 1) {
            return "'".$value;
        }

        return $value;
    }

    /**
     * Defuse every string cell in a row.
     *
     * @param  array<int,mixed>  $row
     * @return array<int,mixed>
     */
    public static function row(array $row): array
    {
        return array_map([self::class, 'cell'], $row);
    }
}
