<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            // Ordered list of {lat,lng} vertices describing the branch's physical
            // premises. Used to verify a diner is on-site when they scan a table
            // QR (dine-in presence check), not for delivery zoning.
            $table->json('geofence')->nullable()->after('longitude');
            // Opt-in: when true and a polygon is present, table-QR sessions are
            // refused unless the scanner's GPS falls inside the polygon.
            $table->boolean('geofence_enabled')->default(false)->after('geofence');
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn(['geofence', 'geofence_enabled']);
        });
    }
};
