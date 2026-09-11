;;; test_pcre.p — suite for LIB * PCRE (run via tools/test-libs.sh)
uses poptest;
uses pcre;

vars start, nchars;

pcre_search('\\d+', 'abc123def45', 1) -> (start, nchars);
check('search start', start, 4);
check('search len', nchars, 3);
pcre_search('\\d+', 'abc123def45', 7) -> (start, nchars);
check('search from', start, 10);
pcre_search('zzz', 'abc', 1) -> (start, nchars);
check('search miss', start, false);

check_true('matches', pcre_matches('c.t', 'the cat sat'));
check_false('matches miss', pcre_matches('^cat', 'the cat'));
check_true('anchors', pcre_matches('^the\\b.*sat$', 'the cat sat'));
check_true('case flag', pcre_matches('(?i)POPLOG', 'poplog'));
check_false('case sensitive', pcre_matches('POPLOG', 'poplog'));
check_true('alternation', pcre_matches('cat|dog', 'hotdog stand'));
check_true('quantifier', pcre_matches('ab{2,3}c', 'abbc'));
check_false('quantifier miss', pcre_matches('ab{2,3}c', 'abc'));
check_true('lookahead', pcre_matches('foo(?=bar)', 'foobar'));
check_false('lookahead miss', pcre_matches('foo(?=bar)', 'foobaz'));

check('first', pcre_first('\\d+', 'order 66 and 99'), '66');
check('first miss', pcre_first('\\d', 'abc'), false);

check('groups', pcre_groups('(\\w+)@(\\w+)\\.com', 'mail bob@example.com now'),
      {'bob@example.com' 'bob' 'example'});
check('groups optional unset', pcre_groups('a(b)?(c)', 'ac'),
      {% 'ac', false, 'c' %});
check('groups no match', pcre_groups('(x)(y)', 'ab'), false);

check('all', pcre_all('\\d+', 'a1b22c333'), ['1' '22' '333']);
check('all none', pcre_all('\\d', 'abc'), []);
check('all words', pcre_all('\\ba\\w*', 'an apple and axe'),
      ['an' 'apple' 'and' 'axe']);

check('split', pcre_split('\\s*,\\s*', 'a, b ,c'), ['a' 'b' 'c']);
check('split none', pcre_split(',', 'abc'), ['abc']);
check('split edges', pcre_split(',', ',a,'), ['' 'a' '']);

check('replace', pcre_replace('\\d+', 'a12b345', '#'), 'a#b#');
check('replace none', pcre_replace('\\d', 'abc', '#'), 'abc');
check('replace ci', pcre_replace('(?i)cat', 'Cat cAt CAT', 'dog'),
      'dog dog dog');

check_true('version', length(pcre_version()) > 0);

check_mishaps('bad pattern', procedure; pcre_matches('(unclosed', 'x') endprocedure);
check_mishaps('non-string', procedure; pcre_matches(42, 'x') endprocedure);

test_summary();
