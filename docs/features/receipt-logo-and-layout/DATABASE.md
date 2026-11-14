# Database — receipt-logo-and-layout

No schema change and no migration, on the POS or in the cloud. The logo is read from the existing `pos_restaurants.logo_bytes` / `logo_mime` / `logo_source` columns (XORD-021, migrations 58-59). The new "print logo" setting is not in the database: it is the key `print_logo` in the till's `config.json` (`PrinterConfig.printLogo`, default true; a file without the key reads as true).
