  $ . $ORIGINAL_DIR/tests/helpers/caml.sh

Can we include the TLM inside a module inside a functor
and then open an instance of that functor?

  $ caml $TESTDIR/open_in_functor
  (Or (String a) (String b))
