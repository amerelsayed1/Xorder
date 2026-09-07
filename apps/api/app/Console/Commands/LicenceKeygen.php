<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

/**
 * Generate the Ed25519 pair that signs POS licence files (POS-BE-015 §1).
 *
 * Prints the secret key for .env and the public key for the Flutter binary.
 * Deliberately does NOT write either to disk: the secret belongs in the
 * deployment's environment, not in the repository, and printing it once forces
 * whoever runs this to put it somewhere on purpose.
 */
class LicenceKeygen extends Command
{
    protected $signature = 'licence:keygen';

    protected $description = 'Generate an Ed25519 key pair for signing POS licences';

    public function handle(): int
    {
        $pair = sodium_crypto_sign_keypair();

        $secret = sodium_crypto_sign_secretkey($pair);
        $public = sodium_crypto_sign_publickey($pair);

        $this->newLine();
        $this->line('<options=bold>1. API — add to .env (never commit):</>');
        $this->newLine();
        $this->line('LICENCE_SIGNING_KEY='.base64_encode($secret));
        $this->line('LICENCE_KEY_ID='.config('licence.key_id', 'v1'));

        $this->newLine();
        $this->line('<options=bold>2. POS — compile into the Flutter binary:</>');
        $this->newLine();
        $this->line('  base64: '.base64_encode($public));
        $this->line('  bytes:  const [ '.implode(', ', array_values(unpack('C*', $public))).' ]');

        $this->newLine();
        $this->warn('Rotation rule: ship the new PUBLIC key in a POS release BEFORE signing');
        $this->warn('anything with it. A till that cannot verify has no way of being told to');
        $this->warn('update — it reports `invalid`, which reads as "my licence is broken".');
        $this->newLine();

        return self::SUCCESS;
    }
}
