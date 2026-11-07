<?php

namespace App\Support;

use App\Models\Restaurant;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Which languages a restaurant writes its content in (XORD-005): names and
 * descriptions of categories, items, combos, areas and so on.
 *
 * It is the restaurant's `bilingual` flag and `default_language`:
 *
 *   Arabic only   bilingual = false, default_language = ar
 *   English only  bilingual = false, default_language = en
 *   Both          bilingual = true  (default_language is the one shown first)
 *
 * **This is content, not the interface.** A waiter can read the dashboard in
 * English while the menu is Arabic-only; the interface language is the user's
 * own choice and nothing here reads it.
 */
final class ContentLanguages
{
    /** @param list<string> $enabled */
    private function __construct(
        private readonly array $enabled,
        private readonly bool $bilingual,
    ) {}

    public static function of(Restaurant $restaurant): self
    {
        $primary = $restaurant->default_language?->value ?? 'ar';
        $bilingual = $restaurant->bilingual !== false;

        $enabled = $bilingual
            ? ($primary === 'ar' ? ['ar', 'en'] : ['en', 'ar'])
            : [$primary];

        return new self($enabled, $bilingual);
    }

    /** @return list<string> Enabled languages, the primary first. */
    public function enabled(): array
    {
        return $this->enabled;
    }

    public function bilingual(): bool
    {
        return $this->bilingual;
    }

    public function primary(): string
    {
        return $this->enabled[0];
    }

    public function isEnabled(string $lang): bool
    {
        return in_array($lang, $this->enabled, true);
    }

    /**
     * The name field to blame when a name is missing, or null when it is fine.
     *
     * Bilingual: one of the two is enough, and [$primaryWhenBilingual] picks
     * which field carries the error (the primary language, or `name_en` as
     * most screens always did — both are on screen, so both are visible).
     * Single language: the enabled one is required — a hidden field that still
     * holds an old translation must not let a cleared visible field through, and
     * the error must land on the field the form actually renders.
     */
    public function missingName(?string $ar, ?string $en, bool $primaryWhenBilingual = false): ?string
    {
        if ($this->bilingual) {
            return (blank($ar) && blank($en))
                ? ($primaryWhenBilingual ? 'name_'.$this->primary() : 'name_en')
                : null;
        }

        $value = $this->primary() === 'ar' ? $ar : $en;

        return blank($value) ? 'name_'.$this->primary() : null;
    }

    /**
     * Validate the name pair of a request, on the right field with the given
     * message. [$partial] is for updates, which may omit the names entirely.
     */
    public static function checkName(
        FormRequest $request,
        Validator $validator,
        string $messageKey,
        bool $partial = false,
        bool $primaryWhenBilingual = false,
    ): void {
        if ($partial && ! $request->has('name_ar') && ! $request->has('name_en')) {
            return;
        }

        $blame = self::of($request->user()->restaurant)
            ->missingName($request->input('name_ar'), $request->input('name_en'), $primaryWhenBilingual);

        if ($blame !== null) {
            $validator->errors()->add($blame, __($messageKey));
        }
    }
}
