<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Runs from the dedicated `scheduler` compose service (php artisan schedule:work).
Schedule::command('subscriptions:process')->dailyAt('03:00');

// Consumer lines rotate their public IP, so each branch's learned customer
// Wi-Fi address is re-derived nightly from a rolling window of sessions.
Schedule::command('branches:learn-egress-ips')->dailyAt('03:30');
