<?php

namespace Tests\Unit;

use App\Support\MenuViewGate;
use Illuminate\Http\Request;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

class MenuViewGateTest extends TestCase
{
    private function request(string $uri, string $userAgent): Request
    {
        return Request::create($uri, 'GET', server: ['HTTP_USER_AGENT' => $userAgent]);
    }

    public function test_real_browser_view_is_counted(): void
    {
        $ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1';

        $this->assertTrue(MenuViewGate::shouldCount($this->request('/menu', $ua)));
    }

    public function test_owner_preview_is_not_counted(): void
    {
        $ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36';

        $this->assertFalse(MenuViewGate::shouldCount($this->request('/menu?preview=1', $ua)));
    }

    #[DataProvider('botUserAgents')]
    public function test_known_bots_are_flagged(string $ua): void
    {
        $this->assertTrue(MenuViewGate::isBot($ua));
    }

    public static function botUserAgents(): array
    {
        return [
            'empty' => [''],
            'facebook unfurl' => ['facebookexternalhit/1.1'],
            'whatsapp preview' => ['WhatsApp/2.23'],
            'googlebot' => ['Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'],
            'uptime monitor' => ['UptimeRobot/2.0'],
            'curl' => ['curl/8.4.0'],
            'python' => ['python-requests/2.31.0'],
        ];
    }

    #[DataProvider('humanUserAgents')]
    public function test_real_browsers_are_not_flagged(string $ua): void
    {
        $this->assertFalse(MenuViewGate::isBot($ua));
    }

    public static function humanUserAgents(): array
    {
        return [
            'iphone safari' => ['Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1'],
            'android chrome' => ['Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36'],
            'desktop chrome' => ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36'],
        ];
    }
}
