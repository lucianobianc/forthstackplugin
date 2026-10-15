\ Run with :ForthStackRun. Labels are ordinary Forth comments.
: birthday 1+ ;
: can-drive 18 >= ;

17 ( LABEL: age )
dup can-drive drop
dup birthday
can-drive
