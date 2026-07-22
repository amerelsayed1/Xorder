<?php

namespace Database\Seeders;

use App\Models\Plan;
use Illuminate\Database\Seeder;

class PlanSeeder extends Seeder
{
    /**
     * Subscription plans catalog (managed at /plans). Mirrors the landing tiers
     * so the two stay consistent. Idempotent: safe to re-run.
     */
    public function run(): void
    {
        $plans = [
            [
                'name' => 'Menu Starter',
                'price' => null, // Free
                'currency' => 'EGP',
                'sort_order' => 1,
                // Digital menu only — no ordering of any kind.
                'feature_keys' => ['qr_menu'],
            ],
            [
                'name' => 'Menu Plus',
                'price' => 749.00,
                'currency' => 'EGP',
                'sort_order' => 2,
                // WhatsApp ordering: cart hands off to WhatsApp. No order
                // management dashboard or customer tracking.
                'feature_keys' => ['qr_menu', 'whatsapp_ordering', 'pickup', 'delivery'],
            ],
            [
                'name' => 'Restaurant Pro',
                'price' => null, // Custom pricing
                'currency' => 'EGP',
                'sort_order' => 3,
                // Full system ordering: durable orders, customer tracking, table
                // service and analytics. Feature::resolve pulls in prerequisites
                // (table_management→dine_in, bill_requests→table_management,
                // customer_tracking→system_ordering).
                'feature_keys' => [
                    'qr_menu', 'whatsapp_ordering', 'system_ordering', 'customer_tracking',
                    'table_management', 'bill_requests', 'internal_reviews', 'product_analytics',
                    'dine_in', 'pickup', 'delivery', 'multi_branch',
                ],
            ],
        ];

        foreach ($plans as $data) {
            Plan::updateOrCreate(['name' => $data['name']], $data);
        }

        $this->command?->info('Seeded '.count($plans).' subscription plans.');
    }
}
