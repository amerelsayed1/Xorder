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
                'features' => [
                    'QR menu',
                    'Menu categories',
                    'Product images',
                    'Price and item updates',
                    'Restaurant information page',
                    'Shareable menu link',
                ],
            ],
            [
                'name' => 'Menu Plus',
                'price' => 749.00,
                'currency' => 'EGP',
                'sort_order' => 2,
                'features' => [
                    'Everything in Menu Starter',
                    'Add to cart',
                    'Direct order submission',
                    'Orders received on WhatsApp',
                    'Pickup, delivery, or table orders (if available)',
                    'Offers / coupons (if available)',
                ],
            ],
            [
                'name' => 'Restaurant Pro',
                'price' => null, // Custom pricing
                'currency' => 'EGP',
                'sort_order' => 3,
                'features' => [
                    'Everything in Menu Plus',
                    'Order management dashboard',
                    'Delivery and pickup management',
                    'Table ordering',
                    'Reports and insights',
                    'Branch support (if available)',
                    'Driver app (if available)',
                ],
            ],
        ];

        foreach ($plans as $data) {
            Plan::updateOrCreate(['name' => $data['name']], $data);
        }

        $this->command?->info('Seeded '.count($plans).' subscription plans.');
    }
}
