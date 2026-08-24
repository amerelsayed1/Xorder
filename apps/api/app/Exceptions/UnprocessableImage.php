<?php

namespace App\Exceptions;

use RuntimeException;

/**
 * The uploaded file passed content-type validation but could not be safely
 * turned into an image — truncated bytes, a decode failure, or dimensions far
 * past what we are willing to rasterise.
 *
 * Distinct from a generic RuntimeException so the controller can answer 422
 * (bad input) instead of 500 (our fault): a storage-write failure still throws
 * RuntimeException and still surfaces as a server error, which is correct.
 */
class UnprocessableImage extends RuntimeException {}
