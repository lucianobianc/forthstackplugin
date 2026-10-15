\ Gforth 0.7.3 proof of concept; loaded BEFORE the unmodified target file.
variable fst-fd
variable fst-sites
variable fst-events
variable fst-active
variable fst-limit
variable fst-max-depth
defer fst-inputs
' noop is fst-inputs

: fst-hex ( addr len -- )
  bounds ?do i c@ 16 /mod
    dup 10 < if 48 else 87 then + emit
    dup 10 < if 48 else 87 then + emit
  loop ;

: fst-unsigned ( u -- )
  0 10 um/mod ?dup if recurse then [char] 0 + emit ;

: fst-number ( n -- )
  dup 0< if [char] - emit negate then fst-unsigned space ;

: fst-immediate? ( addr len -- flag )
  find-name dup 0= if drop false exit then
  name>comp nip ['] execute = ;

: fst-meta { addr len -- id }
  s" M " type
  1 fst-sites +! fst-sites @
  dup fst-number sourceline# fst-number addr source drop - 1+ fst-number
  sourcefilename fst-hex space
  addr len fst-hex space
  latest ?dup if name>string else s" <anonymous>" then fst-hex space
  addr len fst-immediate? if s" opaque" else s" probe" then type cr
  ;

: fst-snapshot { site phase -- }
  fst-active @ 0= if exit then
  fst-events @ fst-limit @ >= if -4096 throw then
  depth { count }
  count 0< if -4 throw then
  count fst-max-depth @ > if -4097 throw then
  sp@ { stack }
  s" E " type fst-events @ fst-number site fst-number phase fst-number count fst-number
  count 0 ?do stack count 1- i - cells + @ fst-number loop cr
  1 fst-events +! ;

: fst-record ( site phase -- )
  ['] fst-snapshot fst-fd @ outfile-execute
  fst-fd @ flush-file throw ;

: fst-emit ( site phase -- )
  swap postpone literal postpone literal postpone fst-record ;

: fst-compiler ( addr len -- ... xt )
  \ The metadata has its own output channel, separate from program stdout.
  2dup ['] fst-meta fst-fd @ outfile-execute >r
  2dup fst-immediate? if rdrop compiler1 exit then
  r@ 0 fst-emit
  compiler1 execute
  r> 1 fst-emit
  ['] noop ;

' before-word defer@ constant fst-old-before
: fst-before ( -- )
  fst-old-before execute
  ['] parser1 defer@ ['] compiler1 = if
    ['] fst-compiler is parser1
  then ;

: fst-load ( -- )
  ['] fst-before is before-word
  s" FST_SOURCE" getenv ['] included catch
  fst-old-before is before-word
  \ INCLUDED restores input state; reset our temporary parser wrapper, too.
  state @ 0= if ['] interpreter1 is parser1 then
  throw ;

: fst-entry ( -- )
  s" FST_ENTRY" getenv find-name dup 0= if drop -13 throw then
  name>int execute ;

: fst-result ( code -- )
  s" X " type fst-number cr ;

: fst-run ( -- )
  s" FST_TRACE" getenv w/o create-file throw fst-fd !
  ['] fst-load catch dup if
    ['] fst-result fst-fd @ outfile-execute
    fst-fd @ close-file throw bye
  then drop
  fst-inputs
  true fst-active !
  0 2 fst-record
  ['] fst-entry catch
  dup 0= if >r 0 3 fst-record r> then
  false fst-active !
  ['] fst-result fst-fd @ outfile-execute
  fst-fd @ close-file throw ;
