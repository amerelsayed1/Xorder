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

// Activity trail is kept for ACTIVITY_LOG_DAYS (default 30) calendar days.
// Monolog rotates by file count, which drifts on idle days — this sweeps by date.
Schedule::command('activity:prune')->dailyAt('03:45');

// The audit trail backs the Super Admin activity screens, so it is kept longer
// than the file mirror (AUDIT_LOG_DAYS, default 90) — but not forever: orders
// are audited, so the table grows with every status transition.
Schedule::command('audit:prune')->dailyAt('04:00');

// Guest paging pairing sessions (shared QR): dead codes are freed on every new
// session already; this removes the rows themselves. Hourly keeps the table tiny.
Schedule::command('pager:prune')->hourly();
