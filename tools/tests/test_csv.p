;;; test_csv.p — suite for LIB * CSV (run via tools/test-libs.sh)
uses poptest;
uses csv;

check('parse simple', csv_parse('a,b,c\n1,2,3\n', `,`),
      [{'a' 'b' 'c'} {'1' '2' '3'}]);
check('parse no trailing nl', csv_parse('a,b', `,`), [{'a' 'b'}]);
check('parse empty fields', csv_parse('a,,c\n', `,`), [{'a' '' 'c'}]);
check('parse quoted comma', csv_parse('"a,b",c\n', `,`), [{'a,b' 'c'}]);
check('parse escaped quote', csv_parse('"say ""hi""",x\n', `,`),
      [{'say "hi"' 'x'}]);
check('parse quoted newline', csv_parse('"line1\nline2",x\n', `,`),
      [{'line1\nline2' 'x'}]);
check('parse crlf rows', csv_parse('a,b\r\nc,d\r\n', `,`),
      [{'a' 'b'} {'c' 'd'}]);
check('parse tsv', csv_parse('a\tb\nc\td\n', `\t`), [{'a' 'b'} {'c' 'd'}]);
check('parse single field rows', csv_parse('x\ny\n', `,`), [{'x'} {'y'}]);

check('gen simple', csv_generate([{'a' 'b'} {'1' '2'}], `,`), 'a,b\n1,2\n');
check('gen quotes sep', csv_generate([{'a,b' 'c'}], `,`), '"a,b",c\n');
check('gen quotes quote', csv_generate([{'say "hi"'}], `,`), '"say ""hi"""\n');
check('gen quotes newline', csv_generate([{'l1\nl2'}], `,`), '"l1\nl2"\n');
check('gen numbers coerced', csv_generate([{1 2.5}], `,`), '1,2.5\n');
check('gen list rows', csv_generate([[% 'a', 'b' %]], `,`), 'a,b\n');

;;; round trip with every awkward feature at once
lconstant rows = [{'plain' 'com,ma' 'qu"ote' 'multi\nline' ''}];
check('round trip', csv_parse(csv_generate(rows, `,`), `,`), rows);

check_mishaps('unterminated quote',
              procedure; csv_parse('"abc', `,`).erase endprocedure);
check_mishaps('bad sep', procedure; csv_parse('a', 'x').erase endprocedure);

test_summary();
