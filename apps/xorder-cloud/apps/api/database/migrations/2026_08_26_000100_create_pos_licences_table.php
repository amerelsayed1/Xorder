<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS licences (POS-BE-015).
     *
     * A licence is its own per-client record, issued from Super Admin — owner
     * decision D6. It is deliberately NOT derived from the tenant's plan or
     * subscription: an on-premises customer may have no subscription row at
     * all, deals carry bespoke terms, and a licence is a historical document
     * whose meaning must not change when a plan is edited later. `plan_id` is
     * kept as a prefill for `features`, not as the source of truth.
     *
     * Additive: no existing table is touched.
     */
    public function up(): void
    {
        Schema::create('pos_licences', function (Blueprint $table) {
            $table->id();

            // A licence always names exactly one client.
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            // The public reference, emitted as the `license_id` claim. NOT the
            // primary key wearing a prefix — that is the Order::code() mistake
            // and it is not repeated here.
            $table->string('licence_ref', 32)->unique();

            // HMAC-SHA256 of the normalised activation key, keyed with APP_KEY.
            //
            // Deliberately NOT bcrypt: activation has to *find* this row from
            // the key alone, and a salted hash is not searchable — you would
            // load every licence and verify against each, which is both slow
            // and a timing oracle. HMAC is deterministic, indexable, and still
            // useless to someone holding only a database dump.
            //
            // Indexed but NOT unique: a renewal reuses the key on a NEW row, so
            // several rows share a hash and activation resolves to the newest
            // non-revoked, non-superseded one. A partial unique index would say
            // this better but is engine-specific, and this codebase runs SQLite
            // in dev and PostgreSQL in production.
            $table->char('key_hash', 64)->index();
            $table->char('key_last_four', 4);

            $table->foreignId('plan_id')->nullable()->constrained()->nullOnDelete();

            $table->timestamp('issued_at');
            $table->timestamp('expires_at');

            // Trade continues this long past expiry; the renewal banner appears
            // this long before it.
            $table->unsignedSmallInteger('grace_days')->default(14);
            $table->unsignedSmallInteger('warn_days')->default(30);

            // Advisory offline — a fresh install cannot see its siblings. Only
            // a server can actually count terminals (POS-BE-016).
            $table->unsignedSmallInteger('max_terminals')->default(1);

            // The islanded check-in window (POS-BE-022). Null = unlimited,
            // which is the correct value for cloud.
            $table->unsignedSmallInteger('max_offline_days')->nullable();

            $table->json('features');
            $table->json('modes');
            $table->json('branch_ids');
            $table->json('fingerprints');

            // The minted artifact, stored verbatim. Signing happens ONCE, at
            // issuance — never on activation. That is what makes re-activation
            // byte-identical and the download and the API response provably the
            // same document.
            $table->text('payload');
            $table->text('signature');
            $table->string('key_id', 8)->default('v1');

            // A renewal writes a new row and points the old one at it, rather
            // than mutating the term in place: overwriting the signed artifact
            // would erase the record of what the customer was actually sold.
            $table->foreignId('superseded_by_id')->nullable()
                ->references('id')->on('pos_licences')->nullOnDelete();

            $table->timestamp('revoked_at')->nullable();
            $table->string('revoked_reason')->nullable();
            $table->timestamp('activated_at')->nullable();

            // Super Admin's commercial note. Never signed, never sent to a till.
            $table->text('notes')->nullable();

            $table->foreignId('created_by_id')->nullable()
                ->references('id')->on('users')->nullOnDelete();

            $table->timestamps();

            $table->index(['restaurant_id', 'expires_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pos_licences');
    }
};
