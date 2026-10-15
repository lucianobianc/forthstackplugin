\ Gforth 0.7.3 proof of concept; loaded BEFORE the unmodified target file.
variable fst-fd
variable fst-sites
variable fst-events
variable fst-active
variable fst-compiling
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

: fst-operation ( addr len -- addr2 len2 )
  2dup fst-immediate? if 2drop s" opaque" exit then
  find-name dup 0= if drop s" literal" exit then
  name>int
  dup ['] dup = if drop s" dup" exit then
  dup ['] drop = if drop s" drop" exit then
  dup ['] swap = if drop s" swap" exit then
  dup ['] over = if drop s" over" exit then
  dup ['] rot = if drop s" rot" exit then
  dup ['] nip = if drop s" nip" exit then
  dup ['] tuck = if drop s" tuck" exit then
  dup ['] 1+ = if drop s" 1+" exit then
  dup ['] 1- = if drop s" 1-" exit then
  dup ['] = = if drop s" =" exit then
  dup ['] <> = if drop s" <>" exit then
  dup ['] < = if drop s" <" exit then
  dup ['] > = if drop s" >" exit then
  dup ['] <= = if drop s" <=" exit then
  dup ['] >= = if drop s" >=" exit then
  dup ['] u< = if drop s" u<" exit then
  dup ['] u> = if drop s" u>" exit then
  dup ['] 0= = if drop s" 0=" exit then
  dup ['] 0< = if drop s" 0<" exit then
  dup ['] 0> = if drop s" 0>" exit then
  dup ['] 0<> = if drop s" 0<>" exit then
  dup ['] + = if drop s" +" exit then
  dup ['] - = if drop s" -" exit then
  dup ['] * = if drop s" *" exit then
  dup ['] / = if drop s" /" exit then
  dup ['] mod = if drop s" mod" exit then
  dup ['] /mod = if drop s" /mod" exit then
  drop s" call" ;

: fst-safe-immediate? ( addr len -- flag )
  find-name name>comp drop
  dup [comp'] ( drop = if drop true exit then
  dup [comp'] \ drop = if drop true exit then
  dup [comp'] ; drop = if drop true exit then
  dup [comp'] if drop = if drop true exit then
  dup [comp'] else drop = if drop true exit then
  dup [comp'] then drop = if drop true exit then
  dup [comp'] begin drop = if drop true exit then
  dup [comp'] while drop = if drop true exit then
  dup [comp'] repeat drop = if drop true exit then
  dup [comp'] until drop = if drop true exit then
  dup [comp'] again drop = if drop true exit then
  dup [comp'] do drop = if drop true exit then
  dup [comp'] ?do drop = if drop true exit then
  dup [comp'] loop drop = if drop true exit then
  dup [comp'] +loop drop = if drop true exit then
  dup [comp'] leave drop = if drop true exit then
  dup [comp'] exit drop = if drop true exit then
  dup [comp'] recurse drop = if drop true exit then
  dup [comp'] [ drop = if drop true exit then
  drop false ;

: fst-meta { addr len -- id }
  s" M " type
  1 fst-sites +! fst-sites @
  dup fst-number sourceline# fst-number addr source drop - 1+ fst-number
  sourcefilename fst-hex space
  addr len fst-hex space
  fst-compiling @ if
    latest ?dup if name>string else s" <anonymous>" then
  else s" <top-level>" then fst-hex space
  addr len fst-immediate? if s" opaque" else s" probe" then type cr
  s" O " type dup fst-number addr len fst-operation type cr ;

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

: fst-trim ( addr len -- addr2 len2 )
  begin dup while over c@ bl <= while 1 /string repeat then
  begin dup while 2dup + 1- c@ bl <= while 1- repeat then ;

: fst-label-info ( -- addr len flag )
  source >in @ /string { addr len }
  addr len [char] ) scan nip { tail }
  tail 0= if 0 0 false exit then
  addr len tail - fst-trim
  dup 6 < if 2drop 0 0 false exit then
  over 6 s" LABEL:" str= 0= if 2drop 0 0 false exit then
  6 /string fst-trim true ;

: fst-label-meta { addr len label-addr label-len -- id }
  addr len fst-meta
  s" L " type dup fst-number label-addr label-len fst-hex cr ;

: fst-annotation ( addr len -- id true | false )
  2dup s" (" str= 0= if 2drop false exit then
  fst-label-info if
    ['] fst-label-meta fst-fd @ outfile-execute true
  else
    2drop 2drop false
  then ;

: fst-compiler ( addr len -- ... xt )
  \ Label probes run at the comment location, without changing comment parsing.
  2dup fst-annotation if 4 fst-emit compiler1 exit then
  \ The metadata has its own output channel, separate from program stdout.
  2dup ['] fst-meta fst-fd @ outfile-execute >r
  2dup fst-immediate? if
    2dup fst-safe-immediate? 0= if r@ 5 fst-emit then
    rdrop 2dup s" ;" str= >r
    compiler1 execute
    r> if false fst-compiling ! true fst-active ! then
    ['] noop exit
  then
  r@ 0 fst-emit
  compiler1 execute
  r> 1 fst-emit
  ['] noop ;

: fst-interpreter { addr len -- xt }
  \ Bracket interpretation during compilation operates on the compiler's stack.
  fst-compiling @ if addr len interpreter1 exit then
  addr len fst-annotation if 4 fst-record addr len interpreter1 exit then
  addr len s" :" str= if
    true fst-compiling ! false fst-active !
    addr len interpreter1 exit
  then
  addr len fst-immediate? if
    addr len fst-safe-immediate? 0= if
      addr len ['] fst-meta fst-fd @ outfile-execute 5 fst-record
    then
    addr len interpreter1 exit
  then
  addr len ['] fst-meta fst-fd @ outfile-execute { site }
  site 0 fst-record
  addr len interpreter1 execute
  state @ if
    true fst-compiling ! false fst-active !
  else
    site 1 fst-record
  then
  ['] noop ;

' before-word defer@ constant fst-old-before
: fst-before ( -- )
  fst-old-before execute
  ['] parser1 defer@ ['] compiler1 = if
    ['] fst-compiler is parser1
  else
    ['] parser1 defer@ ['] interpreter1 = if
      ['] fst-interpreter is parser1
    then
  then ;

: fst-include ( -- )
  s" FST_SNAPSHOT" getenv dup if
    r/o open-file throw s" FST_SOURCE" getenv included1
  else
    2drop s" FST_SOURCE" getenv included
  then ;

: fst-load ( -- )
  ['] fst-before is before-word
  ['] fst-include catch
  fst-old-before is before-word
  \ Restore the outer interpreter even if loading failed inside a definition.
  ['] interpreter1 is parser1 state off
  throw
  fst-compiling @ if -22 throw then ;

: fst-entry ( -- )
  s" FST_ENTRY" getenv find-name dup 0= if drop -13 throw then
  name>int execute ;

: fst-result ( code -- )
  s" X " type fst-number
  fst-compiling @ if 1 else 0 then fst-number cr ;

: fst-session ( -- )
  fst-load
  s" FST_ENTRY" getenv nip if fst-inputs fst-entry then ;

: fst-run ( -- )
  s" FST_TRACE" getenv w/o create-file throw fst-fd !
  true fst-active !
  s" FST_ENTRY" getenv nip 0= if fst-inputs then
  0 2 fst-record
  ['] fst-session catch
  dup 0= if >r 0 3 fst-record r> then
  false fst-active !
  ['] fst-result fst-fd @ outfile-execute
  fst-fd @ close-file throw ;
