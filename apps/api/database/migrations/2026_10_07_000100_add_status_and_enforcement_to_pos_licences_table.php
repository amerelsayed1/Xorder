<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Dashboard-managed online licences (R2, POS-BE-031).
 *
 * `status` is what Super Admin sets — active, suspended, or force-expired —
 * and is authoritative for the ONLINE verdict only (POST /api/pos/license/check).
 * The dates still decide everything else through PosLicence::state(), and are
 * the only signal an islanded till has: a signed file cannot be recalled.
 *
 * `enforcement` says where a till gets its verdict: `online` asks the platform,
 * `offline` trusts the signed file. Backfilled from `kind`, not from
 * `max_offline_days` as the R2.6 draft had it: an offline-kind licence has no
 * tenant, so no terminal of it can ever authenticate to the online check, and
 * calling it `online` would point a till at an endpoint that can only 404.
 *
 * Additive and defaulted; every existing row reads `active`, which changes no
 * verdict — an expired licence is still expired by its dates. Guarded with
 * hasColumn, as this production DB has carried out-of-CI migration state.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('pos_licences', function (Blueprint $table) {
            if (! Schema::hasColumn('pos_licences', 'status')) {
                $table->string('status', 16)->default('active')->index();
            }
            if (! Schema::hasColumn('pos_licences', 'suspended_at')) {
                $table->timestamp('suspended_at')->nullable();
            }
            if (! Schema::hasColumn('pos_licences', 'suspended_reason')) {
                $table->string('suspended_reason')->nullable();
            }
            if (! Schema::hasColumn('pos_licences', 'enforcement')) {
                $table->string('enforcement', 16)->default('online')->index();
            }
        });

        DB::table('pos_licences')->where('kind', 'offline')->update(['enforcement' => 'offline']);
    }

    public function down(): void
    {
        Schema::table('pos_licences', function (Blueprint $table) {
            $table->dropIndex(['status']);
            $table->dropIndex(['enforcement']);
            $table->dropColumn(['status', 'suspended_at', 'suspended_reason', 'enforcement']);
        });
    }
};
