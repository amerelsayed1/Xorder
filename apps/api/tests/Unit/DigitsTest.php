<?php

namespace Tests\Unit;

use App\Support\Digits;
use PHPUnit\Framework\TestCase;

class DigitsTest extends TestCase
{
    public function test_arabic_and_persian_digits_become_latin(): void
    {
        $this->assertSame('01012345678', Digits::latin('٠١٠١٢٣٤٥٦٧٨'));
        $this->assertSame('0123456789', Digits::latin('۰۱۲۳۴۵۶۷۸۹'));
        $this->assertSame('12345', Digits::latin('١٢3٤٥'));
    }

    public function test_the_arabic_decimal_mark_becomes_a_point(): void
    {
        $this->assertSame('125.50', Digits::latin('١٢٥٫٥٠'));
    }

    public function test_the_thousands_mark_and_everything_else_is_left_alone(): void
    {
        $this->assertSame('1٬250', Digits::latin('١٬٢٥٠'));
        $this->assertSame('ab12cd', Digits::latin('ab١٢cd'));
        $this->assertSame('+201012345678', Digits::latin('+٢٠١٠١٢٣٤٥٦٧٨'));
    }
}
