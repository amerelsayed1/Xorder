<?php

namespace App\Http\Requests\Concerns;

use App\Support\Digits;

/**
 * Folds Arabic and Persian digits to Latin in the numeric fields a request
 * declares, before validation (XORD-004), so `numeric` and `min`/`max` see the
 * number the person meant instead of answering "must be a number".
 *
 * A request lists its keys in `numericInputKeys()`; `*` matches every element
 * of a list ("option_groups.*.options.*.price"). Only strings are touched.
 */
trait NormalizesNumericInput
{
    /**
     * @return list<string>
     */
    abstract protected function numericInputKeys(): array;

    protected function prepareForValidation(): void
    {
        $data = $this->all();

        foreach ($this->numericInputKeys() as $key) {
            $data = $this->foldAt($data, explode('.', $key));
        }

        $this->merge($data);
    }

    /**
     * @param  array<int|string, mixed>  $node
     * @param  list<string>  $path
     * @return array<int|string, mixed>
     */
    private function foldAt(array $node, array $path): array
    {
        $head = array_shift($path);

        foreach ($node as $key => $value) {
            if ($head !== '*' && (string) $key !== $head) {
                continue;
            }

            if ($path === []) {
                if (is_string($value)) {
                    $node[$key] = Digits::latin($value);
                }
            } elseif (is_array($value)) {
                $node[$key] = $this->foldAt($value, $path);
            }
        }

        return $node;
    }
}
