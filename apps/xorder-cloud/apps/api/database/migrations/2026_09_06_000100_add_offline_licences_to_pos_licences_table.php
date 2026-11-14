<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Offline licences: a licensed customer who is NOT a cloud tenant.
     *
     * Until now a licence always named a `restaurants` row, so licensing an
     * on-premises customer meant provisioning a full cloud tenant — an admin
     * user, an entitlement set, a subscription — for a business whose data will
     * never touch this platform. That is the wrong record to create: it makes
     * the fleet, the tenant list and every "how many customers do we have?"
     * query answer with businesses we do not host.
     *
     * So `restaurant_id` becomes nullable and the customer's identity moves
     * onto the licence itself. What the platform keeps for an offline client is
     * exactly the licence-management minimum — who owns it, what they bought,
     * when it expires, is it revoked — and nothing operational. There is no
     * tenant for products, orders, branches or sales to hang off, which is the
     * structural version of "no business data is synced".
     *
     * ADDITIVE. Every existing row is a cloud licence and keeps its meaning:
     * `kind` defaults to 'cloud', and dropping a NOT NULL constraint cannot
     * invalidate a row that already satisfies it.
     */
    public function up(): void
    {
        Schema::table('pos_licences', function (Blueprint $table) {
            // 'cloud' | 'offline'. A string rather than a boolean because the
            // third case (a hosted tenant whose tills run on-premises) is a
            // deployment MODE, already carried in modes[], and a boolean here
            // would invite conflating the two.
            $table->string('kind', 16)->default('cloud')->index()->after('licence_ref');

            // The customer, when there is no tenant row to name them. Both feed
            // the signed claims: `tenant_name` is what the till prints, and
            // `tenant_slug` is the identifier it configures itself with.
            //
            // NOT unique: a renewal writes a new row for the same customer, so
            // the slug legitimately repeats. Indexed because activation may
            // still be given one to check against.
            $table->string('customer_name')->nullable()->after('kind');
            $table->string('customer_slug', 64)->nullable()->index()->after('customer_name');

            // Who to call. Commercial contact only — never signed, never sent
            // to a till, and deliberately not a `users` row: an offline
            // customer has no account on this platform and must not get one.
            $table->string('contact_name')->nullable()->after('customer_slug');
            $table->string('contact_email')->nullable()->after('contact_name');
            $table->string('contact_phone', 32)->nullable()->after('contact_email');

            // A licence sold outright. `expires_at` stays populated (with a
            // sentinel far future) rather than becoming nullable, because the
            // claim is required by LicenseClaims.fromJson on every till already
            // in the field — a null would not parse, and licences are verified
            // offline by binaries we cannot update. This flag is what the
            // dashboard reads to print "Lifetime" instead of a date in 2099.
            $table->boolean('lifetime')->default(false)->after('expires_at');
        });

        // Separated from the column additions: this is a constraint change, not
        // an addition, and on SQLite it rebuilds the table. Postgres does it in
        // place as a catalogue update — no rewrite, no lock worth the name.
        Schema::table('pos_licences', function (Blueprint $table) {
            $table->unsignedBigInteger('restaurant_id')->nullable()->change();
        });
    }

    public function down(): void
    {
        // Deliberately NOT restoring the NOT NULL: any offline licence issued
        // since would have to be deleted to satisfy it, and a rollback that
        // destroys sold entitlements is worse than a loose constraint.
        Schema::table('pos_licences', function (Blueprint $table) {
            $table->dropColumn([
                'kind',
                'customer_name',
                'customer_slug',
                'contact_name',
                'contact_email',
                'contact_phone',
                'lifetime',
            ]);
        });
    }
};
