;;; test_utf8.p — suite for LIB * UTF8 (run via tools/test-libs.sh)
uses poptest;
uses utf8;

lconstant
    e_acute = consstring(16:C3, 16:A9, 2),              ;;; é  U+00E9
    po      = consstring(16:E3, 16:83, 16:9D, 3),       ;;; ポ U+30DD
    clef    = consstring(16:F0, 16:9D, 16:84, 16:9E, 4),;;; 𝄞 U+1D11E
    mixed   = 'a' <> e_acute <> po <> clef <> 'z';

check_true('valid ascii', utf8_valid('hello'));
check_true('valid empty', utf8_valid(''));
check_true('valid mixed', utf8_valid(mixed));
check_false('invalid lone continuation', utf8_valid(consstring(16:80, 1)));
check_false('invalid truncated 2byte', utf8_valid(consstring(16:C3, 1)));
check_false('invalid truncated 4byte', utf8_valid(consstring(16:F0, 16:9D, 2)));
check_false('invalid overlong C0', utf8_valid(consstring(16:C0, 16:80, 2)));
check_false('invalid overlong E0', utf8_valid(consstring(16:E0, 16:80, 16:80, 3)));
check_false('invalid surrogate', utf8_valid(consstring(16:ED, 16:A0, 16:80, 3)));
check_false('invalid F5 lead', utf8_valid(consstring(16:F5, 16:80, 16:80, 16:80, 4)));
check_false('invalid bad continuation', utf8_valid(consstring(16:C3, 16:29, 2)));

check('length ascii', utf8_length('abc'), 3);
check('length empty', utf8_length(''), 0);
check('length mixed', utf8_length(mixed), 5);
check('length clef', utf8_length(clef), 1);

check('code ascii', utf8_code(1, 'abc'), `a`);
check('code accent', utf8_code(2, mixed), 16:E9);
check('code katakana', utf8_code(3, mixed), 16:30DD);
check('code astral', utf8_code(4, mixed), 16:1D11E);
check('code last', utf8_code(5, mixed), `z`);

check('substring middle', utf8_substring(2, 3, mixed), e_acute <> po <> clef);
check('substring head', utf8_substring(1, 1, mixed), 'a');
check('substring tail', utf8_substring(5, 1, mixed), 'z');
check('substring to end', utf8_substring(4, 2, mixed), clef <> 'z');
check('substring zero', utf8_substring(3, 0, mixed), '');

check('explode/cons round trip',
      consutf8(#| utf8_explode(mixed) |#), mixed);
check('consutf8 basic', consutf8(16:E9, 16:30DD, 2), e_acute <> po);
check('consutf8 empty', consutf8(0), '');

vars total = 0;
utf8_appcodes(mixed, procedure(c); total + c -> total endprocedure);
check('appcodes sum', total, `a` + 16:E9 + 16:30DD + 16:1D11E + `z`);

check_mishaps('length on bad', procedure; utf8_length(consstring(16:80, 1)).erase endprocedure);
check_mishaps('code past end', procedure; utf8_code(9, 'ab').erase endprocedure);
check_mishaps('substring past end', procedure; utf8_substring(2, 5, 'ab').erase endprocedure);
check_mishaps('consutf8 surrogate', procedure; consutf8(16:D800, 1).erase endprocedure);
check_mishaps('consutf8 too big', procedure; consutf8(16:110000, 1).erase endprocedure);

test_summary();
