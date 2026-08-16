<?php

namespace App\Support;

/**
 * Normalises a client IP into the token branch egress matching compares on.
 *
 * IPv4 is compared exactly — a branch's NAT presents a single address to the
 * internet, so every device on its Wi-Fi arrives from that one value.
 *
 * IPv6 is compared on the /64 prefix instead. Phones rotate the interface half
 * of a v6 address constantly (SLAAC privacy extensions), so the full address
 * differs between two visits by the same device on the same network, while the
 * /64 is the network the ISP delegated to that line. Comparing full v6
 * addresses would simply never match.
 */
final class EgressIp
{
    /**
     * @return string|null the comparison token, or null if $ip is not a usable address
     */
    public static function normalize(?string $ip): ?string
    {
        if ($ip === null || $ip === '') {
            return null;
        }

        if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) !== false) {
            return $ip;
        }

        if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) === false) {
            return null;
        }

        $packed = inet_pton($ip);
        if ($packed === false) {
            return null;
        }

        // Keep the routing half (first 8 bytes), zero the interface half.
        $prefix = inet_ntop(substr($packed, 0, 8).str_repeat("\0", 8));

        return $prefix === false ? null : $prefix.'/64';
    }
}
