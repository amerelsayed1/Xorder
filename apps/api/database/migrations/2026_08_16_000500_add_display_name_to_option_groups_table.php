<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The heading a diner sees above this group's choices, kept apart from the
     * name the owner files it under.
     *
     * A shared group is one row reused across many items, so its name has two
     * jobs that pull in opposite directions: in the Extras library it has to be
     * findable among dozens ("Sizes — pizza"), and on the menu it has to read
     * as a question to the diner ("Choose your size"). One column could only
     * ever serve one of them.
     *
     * Nullable, and the menu falls back to `name_*` when it is blank — so every
     * existing group keeps rendering exactly as it does today and an owner with
     * one good name never has to type it twice.
     */
    public function up(): void
    {
        Schema::table('option_groups', function (Blueprint $table) {
            $table->string('display_name_ar', 150)->nullable()->after('name_en');
            $table->string('display_name_en', 150)->nullable()->after('display_name_ar');
        });
    }

    public function down(): void
    {
        Schema::table('option_groups', function (Blueprint $table) {
            $table->dropColumn(['display_name_ar', 'display_name_en']);
        });
    }
};
