<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Link orders to the customer directory. customer_name/customer_phone stay as a
 * snapshot of what was typed; customer_id points at the deduped directory row.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->foreignId('customer_id')->nullable()->after('restaurant_id')->constrained()->nullOnDelete();
            $table->foreignId('customer_address_id')->nullable()->after('customer_id')->nullOnDelete()->constrained('customer_addresses');
            $table->string('order_type', 20)->nullable()->after('customer_phone'); // pickup | delivery | dine_in
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropConstrainedForeignId('customer_id');
            $table->dropConstrainedForeignId('customer_address_id');
            $table->dropColumn('order_type');
        });
    }
};
