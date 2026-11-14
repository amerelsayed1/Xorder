<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('options', function (Blueprint $table) {
            // Sale price for a size/variant option, so a sized item can show
            // "was 120, now 100" per size the way a flat-priced item already
            // does. Nullable — an option without a sale keeps `price` as its
            // only figure, which is every existing row.
            $table->decimal('discounted_price', 10, 2)->nullable()->after('price');
        });
    }

    public function down(): void
    {
        Schema::table('options', function (Blueprint $table) {
            $table->dropColumn('discounted_price');
        });
    }
};
