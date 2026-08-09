/* examples/secure_notes.p -- LIB JSON + LIB CRYPTO composed.

   A miniature end-to-end "secure notes" pipeline, the shape of most
   real API work:

     1. build structured data and serialise it   (json_generate)
     2. sign it for transport                    (crypto_hmac_hex)
     3. verify + parse on the receiving side     (json_parse)
     4. seal it at rest under a password         (crypto_pbkdf2 + crypto_encrypt)
     5. reopen it -- and show tampering fails    (crypto_decrypt -> false)

   Run:   ./poplog target/pop/basepop11 examples/secure_notes.p
   Needs the crypto shim built once:  tools/build-popcrypto.sh
   Docs:  HELP * JSON, HELP * CRYPTO, TEACH * JSON
*/

uses json;
uses crypto;

;;; --- 1. structured data -> JSON ---------------------------------------
vars note = newmapping([], 8, false, true);
'shopping'                      -> note('title');
{% 'oat milk', 'firmware', 42 %} -> note('items');
true                            -> note('urgent');

vars payload = json_generate(note);
'payload:   ' >< payload =>

;;; --- 2. sign it (HMAC-SHA256, as an API would) ------------------------
vars api_key = crypto_random(32);
vars sig = crypto_hmac_hex('sha256', api_key, payload);
'signature: ' >< sig =>

;;; --- 3. receiver: verify then parse -----------------------------------
if crypto_hmac_hex('sha256', api_key, payload) = sig then
    'verified:  signature good, parsing...' =>
    json_parse(payload)('items')(1) =>
else
    'REJECTED: bad signature' =>
endif;

;;; --- 4. seal at rest under a password ----------------------------------
vars salt = crypto_random(16);
vars key = crypto_pbkdf2('sha256', 'correct horse battery staple',
                         salt, 100000, 32);
vars blob = crypto_encrypt(key, payload);
'sealed:    ' >< length(blob) >< ' bytes (nonce + ciphertext + tag)' =>

;;; --- 5. reopen it, and prove tampering is caught -----------------------
'reopened:  ' >< crypto_decrypt(key, blob) =>

vars evil = blob <> nullstring;             ;;; a copy...
(subscrs(13, evil) ||/& 255) -> subscrs(13, evil);   ;;; ...one byte flipped
if crypto_decrypt(key, evil) = false then
    'tampered:  decrypt refused (authentication failed) -- as it should' =>
endif;
