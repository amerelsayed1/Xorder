<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        // Login moves from email to username. Add the column nullable first so we
        // can backfill existing rows, then lock it down to NOT NULL + unique.
        Schema::table('users', function (Blueprint $table) {
            $table->string('username')->nullable()->after('name');
        });

        $used = [];
        foreach (DB::table('users')->select('id', 'email')->orderBy('id')->get() as $u) {
            $base = Str::of((string) ($u->email ?? ''))
                ->before('@')->lower()->replaceMatches('/[^a-z0-9._-]/', '')->toString();
            if ($base === '') {
                $base = 'user';
            }

            $username = $base;
            $i = 1;
            while (in_array($username, $used, true) || DB::table('users')->where('username', $username)->exists()) {
                $username = $base.(++$i);
            }
            $used[] = $username;

            DB::table('users')->where('id', $u->id)->update(['username' => $username]);
        }

        Schema::table('users', function (Blueprint $table) {
            $table->string('username')->nullable(false)->change();
            $table->unique('username');
            // Email is no longer required for sign-in.
            $table->string('email')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['username']);
            $table->dropColumn('username');
        });
    }
};
