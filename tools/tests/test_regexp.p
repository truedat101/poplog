;;; test_regexp.p — suite for LIB * REGEXP (run via tools/test-libs.sh)
;;; Pattern syntax is Ved style (REF REGEXP): @. any, @* star,
;;; @[..@] class, @a @z anchors, @< @> word boundaries.
uses poptest;
uses regexp;

vars start, nchars;

regexp_search('d@.@*s', 'this string does match', 1) -> (start, nchars);
check('search start', start, 13);
check('search len', nchars, 4);
regexp_search('zzz', 'abc', 1) -> (start, nchars);
check('search miss', start, false);
regexp_search('a', 'banana', 3) -> (start, nchars);
check('search from', start, 4);

check_true('matches', regexp_matches('str@.ng', 'this string'));
check_false('matches miss', regexp_matches('@astring', 'this string'));
check_true('anchor start', regexp_matches('@athis', 'this string'));
check_true('anchor end', regexp_matches('string@z', 'this string'));
check_false('anchor end miss', regexp_matches('this@z', 'this string'));

check('first', regexp_first('@[0-9@]@[0-9@]@*', 'ab12cd345'), '12');
check('first miss', regexp_first('@[0-9@]', 'abc'), false);
check('first class', regexp_first('@[aeiou@]', 'xyzu'), 'u');

check('all', regexp_all('@[0-9@]@[0-9@]@*', 'a12b345c6'), ['12' '345' '6']);
check('all none', regexp_all('@[0-9@]', 'abc'), []);
check('all word boundary', regexp_all('@<a@[a-z@]@*', 'an apple and axe'),
      ['an' 'apple' 'and' 'axe']);

check('split', regexp_split('@[,;@]', 'a,b;c'), ['a' 'b' 'c']);
check('split multi', regexp_split('@[\s@]@[\s@]@*', 'a b  c'), ['a' 'b' 'c']);
check('split none', regexp_split('@[,@]', 'abc'), ['abc']);
check('split edges', regexp_split(',', ',a,'), ['' 'a' '']);

check('replace', regexp_replace('@[0-9@]@[0-9@]@*', 'a12b345', '#'), 'a#b#');
check('replace none', regexp_replace('@[0-9@]', 'abc', '#'), 'abc');
check('replace grows', regexp_replace('b', 'abc', 'BBB'), 'aBBBc');
check('replace anchored', regexp_replace('@ax', 'xyx', 'Q'), 'Qyx');

;;; the cache returns the same compiled procedure for a repeated pattern
check_true('cache warm', regexp_matches('cache@.test', 'cache-test'));
check_true('cache reuse', regexp_matches('cache@.test', 'cacheXtest'));

check_mishaps('bad pattern', procedure; regexp_matches('@[a-z', 'x').erase endprocedure);
check_mishaps('non-string pattern', procedure; regexp_matches(42, 'x').erase endprocedure);
check_mishaps('bad start', procedure; regexp_search('a', 'x', 0) -> (start, nchars) endprocedure);

test_summary();
