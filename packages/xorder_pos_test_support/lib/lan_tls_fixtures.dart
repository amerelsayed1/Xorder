/// Two throwaway TLS identities for the LAN-encryption tests. **Test only** —
/// the private key below protects nothing and is published on purpose.
///
/// Shaped exactly as `installer/provision.ps1` shapes the server's
/// certificate, so the handshake tests also check that Dart accepts that shape
/// as its own trust anchor: self-signed, `CA:TRUE` with `pathlen:0`,
/// key usage `digitalSignature, keyEncipherment, keyCertSign`, EKU
/// `serverAuth`, SAN `DNS:localhost, IP:127.0.0.1`, RSA 2048, SHA-256, 825
/// days. Made with OpenSSL 3.0 on 25 Oct 2026:
///
/// ```
/// openssl req -x509 -newkey rsa:2048 -nodes -keyout a.key -out a.crt \
///   -days 825 -sha256 -config ext.cnf -extensions v3
/// ```
///
/// with `ext.cnf` holding `[v3] basicConstraints = critical, CA:TRUE,
/// pathlen:0`, `keyUsage = critical, digitalSignature, keyEncipherment,
/// keyCertSign`, `extendedKeyUsage = serverAuth`, `subjectKeyIdentifier =
/// hash`, `subjectAltName = DNS:localhost, IP:127.0.0.1` and `CN =
/// xorder-test-server`. **They expire on 27 Jan 2029**; regenerate both with
/// the command above, and update the fingerprints, when
/// `lan_tls_handshake_test.dart` says so.
library;

/// `openssl x509 -noout -fingerprint -sha256`, lower-cased, colons dropped.
const fixtureASha256 =
    '87b82b031b800c185699625c91ad20edb466ba9231a0955118ded039cd6ba66a';
const fixtureBSha256 =
    'f0f916c31dbdc04379c0018b19d08e5b890e3dbf3e07822dbdc191743d601943';

/// `notAfter=Jan 27 00:23:20 2029 GMT`, the same for both.
final fixtureNotAfter = DateTime.utc(2029, 1, 27, 0, 23, 20);

const fixtureACertificate = '''
-----BEGIN CERTIFICATE-----
MIIDaDCCAlCgAwIBAgIUHqnujFv9IwrATA04cLW4Su2tm8AwDQYJKoZIhvcNAQEL
BQAwMjEbMBkGA1UEAwwSeG9yZGVyLXRlc3Qtc2VydmVyMRMwEQYDVQQKDApYT3Jk
ZXIgUE9TMB4XDTI2MTAyNTAwMjMyMFoXDTI5MDEyNzAwMjMyMFowMjEbMBkGA1UE
AwwSeG9yZGVyLXRlc3Qtc2VydmVyMRMwEQYDVQQKDApYT3JkZXIgUE9TMIIBIjAN
BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7JL7qfARinO/4YX3wDcYcrUGNzAE
eH1paMcJburUDK1n/AbsQrTlD3+LyuCGCi1lJMzuaIfy1PxV729zK3RmMB+9l/h8
fnHeo3ZrqHV9LdltZmhvXMnsbnSw/4Z1GyQiPlONjStSluFkZQQmXGVThNlbeoY2
YMkgsOeXxUuFSwJw4v9M/BUa2AzVhW0g4x0Q2LwwpHUJSHjievvytI0HPZ5QGlCs
aE65JZ7dWP3dmYobht8/hZ3JaoehR4HqF1UbOWiGmrNefD0Gxah1aVvmF1Nj4idG
8WchYJxBjTnhWdGbNoX2k+fUcuchLnpGC8GZiDAaRM82MVvfTVISXQxYgQIDAQAB
o3YwdDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwICpDATBgNVHSUE
DDAKBggrBgEFBQcDATAdBgNVHQ4EFgQUUMAVlOzD41blLk5aOzHgDXCc4DIwGgYD
VR0RBBMwEYIJbG9jYWxob3N0hwR/AAABMA0GCSqGSIb3DQEBCwUAA4IBAQBgSAp3
2by4qaQETPVSyKW8f3myGqLhbPhxs0XRwYTlnvO8azCTEZZBwPvMkmAyW1JNwDz2
vlrGLJpSPu/dV0FqYurUEqehFH/GgBDIMV8FW5ySI1+tspGUJdwgejCfPT6O+p12
+PLK4VBYYKV+1iiFTS/R3HZpb6Y4lbfHsrL/hc8yC0KrtpjrinA3sXVhi0yaFEoH
qmVbkkrdXJuVF8iqmyWIYjHDTJoYxgPxd7TRq9PqyLt3P21BuV4MGI5Xi+qfwQw9
3pq0HW98NEfYI8ZnqdmTd0apBOldkw4peOcu/SSdHUXS/7REedF9h+u01SKQag0s
wKRdcUdxSB+lekbe
-----END CERTIFICATE-----
''';

const fixtureAKey = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDskvup8BGKc7/h
hffANxhytQY3MAR4fWloxwlu6tQMrWf8BuxCtOUPf4vK4IYKLWUkzO5oh/LU/FXv
b3MrdGYwH72X+Hx+cd6jdmuodX0t2W1maG9cyexudLD/hnUbJCI+U42NK1KW4WRl
BCZcZVOE2Vt6hjZgySCw55fFS4VLAnDi/0z8FRrYDNWFbSDjHRDYvDCkdQlIeOJ6
+/K0jQc9nlAaUKxoTrklnt1Y/d2ZihuG3z+Fnclqh6FHgeoXVRs5aIaas158PQbF
qHVpW+YXU2PiJ0bxZyFgnEGNOeFZ0Zs2hfaT59Ry5yEuekYLwZmIMBpEzzYxW99N
UhJdDFiBAgMBAAECggEAH2KelZx+Tz5s8ef6htsoWKtwcCjkJvIIZnilZTwtNqNY
vMRUWsMx8lzq+FbSIY6FMR0o8eA7VItHgVTpVBYEqpTDa+Jw7buAnHIM9VPk8Ay8
6U2onIhDYCIGC1hUt+2Sx28BQ/2/3rl3PrmOt0pQCrtlWfttQmjcd+u5pFiRDfK7
IRTL4Qj8/XUdBjrZR/zHZAnT3dSWQPaj8DL5igYhoOQ/Cjagfw2uzozvyyv5ESSA
gj6N20GHaheWYO3LcsB8s/lAl8l6kZ/WKfpGblcQt5jyYQhAGFozg5ZTI+5eyHFY
ouKLp5fUv7+oX2l3GCeb8hPI8u7uE3ntRB6hEQWG+wKBgQD9R2GFALGEadB77joJ
d93OmJruDwbiz4rNoxgFyQ2S5iwgUif1mgqFyZufQz3ZV30Zc/UhLsq98VKWu/pK
ze9nbio2feO/DVsRqm1v9fRLOcOjcB70M7uHOc9insDXQNKy8gBYY7ucZQ7SJgHt
ySi3Kvc/c3yr15uZfAeRLd3ihwKBgQDvHahSwYzljEe7Bm16eRlD2IozceSSOIoQ
ObDZFuhq3+wWH2k/urIW4VtfaYoglGN+vzBeYp67kulizXqgWGadzOxLhKSQuQ37
eMLKMQnLhEhlJ73ioVYo7me9Mi3CgqL7KfGHVeuUW73Vx/LUyiLewHS6aIF1gc81
V6HFV63GtwKBgG6OfPvwjIxPIAkouL6vSuvGY0Js3sWccGtIuNC1rS4lOLe3BOhJ
IDS8Byki0dmQPfQhUKv2X9s/fpx7W0rRz6GnTdfRZdtcehcg/Ho1szgu873g0DIq
br4dNvBGeci76/zec9YhWqBu4GRM4OSpvRMPNzPENnRQPgRmRmtRyRv7AoGBAOBM
jayzapuZL2A8801Dc3O1GE6Rs7uF1dzKgR3i4zn9utQ1uuDRHGViF/g0ZCGTkJFA
fvrKv+NsOAk6fqESy4+SvsVIM6aeMIOIEBDiVzHVcKOS2AhTFyNmH2HWRB6FtKSt
/6bX7hhIxpZW7W61/me9WMHTbjzv+5MqFNGtIZGZAoGATYgPrEbZlKBH3+VQnYaA
TaxDqtrMumOiUBjkRvh3KJCgGW0pnNeYsen+4o0TmZkOuSWg/f87ioJNpyPfXSwT
TiXmrucwLLGds7JuPsRKti6RkLsVx1xNEjOlOHI1AYW0UkwH5+l9DjOZf80cV4jc
UeDyi6Hiperp7I7wUHXiI6k=
-----END PRIVATE KEY-----
''';

const fixtureBCertificate = '''
-----BEGIN CERTIFICATE-----
MIIDaDCCAlCgAwIBAgIUVJ1Own9B4tbXZnAhbBr4dYJl4R0wDQYJKoZIhvcNAQEL
BQAwMjEbMBkGA1UEAwwSeG9yZGVyLXRlc3Qtc2VydmVyMRMwEQYDVQQKDApYT3Jk
ZXIgUE9TMB4XDTI2MTAyNTAwMjMyMFoXDTI5MDEyNzAwMjMyMFowMjEbMBkGA1UE
AwwSeG9yZGVyLXRlc3Qtc2VydmVyMRMwEQYDVQQKDApYT3JkZXIgUE9TMIIBIjAN
BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsf9z7Kyj8+9fLcCCWP2dF9ABsgNI
WHd7S9w98iTa3piAJcNCAolMHW+jlocChOxIdqjPnXd9YKDZma1ePmEb6WXcQdlK
/4OYZWMsP4sIcJXDup5zW7E3heIULLBlsylnYAUYTSY9rX5mhANNpa8CTvQt8LzE
7yMZNmNeE9r2Ahzxkj2IczG3PWGNftASB8gIC51w8+jvFyHQP73r0obdCzNyC7Ej
fwviUN0dJylptsJHrOkXjBQGFOIyiX+Qqu9D/GbecGh/1kN4PPu9hTqZj3tZvoNn
vebVoK+EIXLrN2b3zHVToRh0jSBUv9fQIm34fFAguVjdQq2bABTZqAggSQIDAQAB
o3YwdDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwICpDATBgNVHSUE
DDAKBggrBgEFBQcDATAdBgNVHQ4EFgQUOIG6pGvKPSSf4ao26DGVog3Lfs4wGgYD
VR0RBBMwEYIJbG9jYWxob3N0hwR/AAABMA0GCSqGSIb3DQEBCwUAA4IBAQAYV44v
eGmzLfvv2L7Gi3Uu1yFsMZODOLd3f77fzyz8ckxbNTjjFhc8Z/rDie6dF6URQzeU
AWDJ6TtpQ8B4bRG8k1Ymr0uWyypa36CeuzFkXaBwNLByX96vuo9M/OnOgp7wVZBa
yl9h/FHrQFEb/JTbapwac2OeMACpixGd6IfXZtu4jtFnIc3EBAn4uYiABGSHWoO+
oyg5arfDeW1OrJ9vvAh/PfP3iE6jZL/qsp3jTmadJInnYruXT1xMLq34K2E2PB8t
Z63hTPFmwqqHFUn8J2pjx2cpgjBWoX/03CFB4XHgP5VTmNAFvo3LjrdL8PVPh871
/X1C/54hQji/QdRm
-----END CERTIFICATE-----
''';
