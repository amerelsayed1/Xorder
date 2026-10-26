<?php

namespace App\Http\Requests\Concerns;

use App\Support\ContentLanguages;

/**
 * An update never blanks the text of a language the restaurant has switched off
 * (XORD-005).
 *
 * The dashboard forms load both languages and post both back, so a hidden field
 * normally returns its stored value. Anything else that writes through the same
 * request — a script, an import, an older client — may send `name_en: null` for
 * a language nobody is looking at. That would erase a translation the owner
 * will want back the day they switch the language on again, so a BLANK value
 * for a disabled language is dropped from the validated data and the stored text
 * stays. A non-blank value is still stored: writing a translation is allowed,
 * erasing one by omission-in-spirit is not.
 *
 * Works beside other request traits: it overrides `validated()` rather than a
 * lifecycle hook.
 */
trait PreservesDisabledLanguages
{
    /** The translated column pairs to protect: `name` means name_ar / name_en. */
    protected function translatedFields(): array
    {
        return ['name', 'description'];
    }

    public function validated($key = null, $default = null)
    {
        $data = parent::validated();

        $languages = ContentLanguages::of($this->user()->restaurant);
        foreach (['ar', 'en'] as $lang) {
            if ($languages->isEnabled($lang)) {
                continue;
            }
            foreach ($this->translatedFields() as $field) {
                $column = "{$field}_{$lang}";
                if (array_key_exists($column, $data) && blank($data[$column])) {
                    unset($data[$column]);
                }
            }
        }

        return $key === null ? $data : data_get($data, $key, $default);
    }
}
