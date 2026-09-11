; Vendored from IoTone/tree-sitter-pop11 (source of truth) — keep in sync.
; Pop-11 highlighting — tree-sitter-pop11

(line_comment) @comment
(block_comment) @comment

(string) @string
(character) @character
(number) @number
(word_literal) @string.special.symbol

(section_path) @module
(matchvar) @variable.parameter
(directive) @keyword.directive

(operator) @operator

; Block-structure keywords
[
  "define" "enddefine"
  "procedure" "endprocedure"
  "if" "endif" "unless" "endunless"
  "then" "do" "else" "elseif" "elseunless"
  "while" "endwhile" "until" "enduntil"
  "for" "endfor" "fast_for" "endfast_for"
  "foreach" "endforeach" "forevery" "endforevery"
  "repeat" "endrepeat" "fast_repeat" "endfast_repeat"
  "section" "endsection" "lblock" "endlblock"
  "exload" "endexload" "defmethod" "enddefmethod"
  "flavour" "endflavour" "vedset" "endvedset"
  "switchon" "endswitchon" "go_on" "endgo_on"
  "uses" "fastprocs" "nonsyntax"
] @keyword

(stray_keyword) @keyword

(define_modifier) @keyword.modifier
(define_form (identifier) @keyword.modifier)

(declaration kind: _ @keyword)
(procedure_type "procedure" @keyword.modifier)

; The defined name
(definition name: (identifier) @function)
(definition name: (section_path) @function)

; Control-transfer builtins (syntax procedures)
((identifier) @keyword.control
 (#any-of? @keyword.control
  "quitif" "quitunless" "quitloop" "nextif" "nextunless" "nextloop"
  "return" "returnif" "returnunless" "goto" "chain" "chainfrom"))

((identifier) @boolean
 (#any-of? @boolean "true" "false"))

((identifier) @function.builtin
 (#any-of? @function.builtin
  "npr" "pr" "printf" "mishap" "apply" "valof" "identof"
  "hd" "tl" "front" "back" "conspair" "destpair" "length"
  "isstring" "isword" "isnumber" "isprocedure" "isinteger" "islist"
  "consword" "consstring" "subscrs" "substring" "issubstring"
  "sysobey" "sysopen" "sysclose" "syssort"))

[ "[" "]" "{" "}" "(" ")" ] @punctuation.bracket
[ ";" "," "%" ] @punctuation.delimiter
[ "#_<" ">_#" ] @keyword.directive
