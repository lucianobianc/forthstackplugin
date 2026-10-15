\ No tracing annotations: the loader instruments compilation in memory.
: birthday ( n -- n+1 )
  1+
;

: example ( -- n )
  15
  birthday
  dup 18 >= if
    100 +
  else
    2 +
  then
  3 0 do
    i +
  loop
;
