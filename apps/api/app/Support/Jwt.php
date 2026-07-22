<?php

namespace App\Support;

use App\Models\User;
use Firebase\JWT\BeforeValidException;
use Firebase\JWT\ExpiredException;
use Firebase\JWT\JWT as FirebaseJwt;
use Firebase\JWT\Key;
use Firebase\JWT\SignatureInvalidException;

/**
 * Mint and verify stateless API access tokens (JWT / HS256).
 *
 * Tokens are self-contained: they carry the user id and the tenant the token
 * was minted for, so an authenticated request needs a single lookup (to confirm
 * the account is still active) rather than a session store.
 */
class Jwt
{
    /** Issue a signed access token for the given user. */
    public static function issue(User $user): string
    {
        $now = time();

        $payload = [
            'iss' => (string) config('app.url'),
            'sub' => $user->getKey(),
            'iat' => $now,
            'nbf' => $now,
            'exp' => $now + (int) config('jwt.ttl') * 60,
            // Bind the token to the restaurant it was issued for so a stale
            // token can't outlive a tenant reassignment.
            'rid' => $user->restaurant_id,
        ];

        return FirebaseJwt::encode($payload, self::secret(), (string) config('jwt.algo'));
    }

    /**
     * Verify a token and return its claims, or null if it is missing,
     * malformed, expired, or the signature does not match.
     *
     * @return array<string, mixed>|null
     */
    public static function parse(string $token): ?array
    {
        try {
            return (array) FirebaseJwt::decode($token, new Key(self::secret(), (string) config('jwt.algo')));
        } catch (ExpiredException|SignatureInvalidException|BeforeValidException|\UnexpectedValueException|\DomainException) {
            return null;
        }
    }

    private static function secret(): string
    {
        $secret = (string) config('jwt.secret');

        if ($secret === '') {
            throw new \RuntimeException('JWT_SECRET is not set. Run `php artisan key:generate` equivalent for JWT or set JWT_SECRET in the environment.');
        }

        return $secret;
    }
}
