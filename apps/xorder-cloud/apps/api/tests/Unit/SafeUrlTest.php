<?php

namespace Tests\Unit;

use App\Support\SafeUrl;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/** Scheme allowlist for tenant URLs that end up in an href. */
class SafeUrlTest extends TestCase
{
    public static function dangerous(): array
    {
        return [
            ['javascript:alert(1)'],
            ['JaVaScRiPt:alert(1)'],
            ['  javascript:alert(1)  '],
            ['javascript://comment%0Aalert(1)'],
            ['data:text/html,<script>alert(1)</script>'],
            ['vbscript:msgbox(1)'],
            ['file:///etc/passwd'],
        ];
    }

    #[DataProvider('dangerous')]
    public function test_dangerous_schemes_are_dropped(string $url): void
    {
        $this->assertNull(SafeUrl::forLink($url));
    }

    public static function safe(): array
    {
        return [
            ['https://g.page/r/abc/review'],
            ['http://example.test/x?a=1&b=2'],
            ['mailto:hi@example.test'],
            ['tel:+201000000000'],
            ['//cdn.example.test/x'],
            ['/relative/path'],
        ];
    }

    #[DataProvider('safe')]
    public function test_safe_urls_pass_through_unchanged(string $url): void
    {
        $this->assertSame($url, SafeUrl::forLink($url));
    }

    public function test_empty_values_collapse_to_null(): void
    {
        $this->assertNull(SafeUrl::forLink(null));
        $this->assertNull(SafeUrl::forLink(''));
        $this->assertNull(SafeUrl::forLink('   '));
    }
}
