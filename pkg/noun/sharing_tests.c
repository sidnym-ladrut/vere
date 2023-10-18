/// @file

#include "noun.h"

/* share_foobar(): noun -> [[%foo noun] [%bar noun]]
 */
u3_noun
share_foobar(u3_noun a)
{
  u3_atom foo = u3i_string("foo");
  u3_atom bar = u3i_string("bar");

  return u3nc(
    u3nc(foo, _(u3a_is_cat(a)) ? a : u3k(a)),
    u3nc(bar, _(u3a_is_cat(a)) ? a : u3k(a))
  );
}

/* _setup(): prepare for tests.
*/
static void
_setup(void)
{
  u3m_init(1 << 26);
  u3m_pave(c3y);
}

/* _test_sharing(): verify that `share_foobar` is working properly
*/
static c3_i
_test_sharing(void)
{
  c3_i ret_i = 1;

  { // atom (cat) test //
    u3_atom baz = u3i_string("baz");
    u3_noun pro = share_foobar(baz);

    c3_c* pri = u3m_pretty(pro);
    if ( 0 != strcmp("[[%foo %baz] %bar %baz]", pri) ) {
      fprintf(stderr, "structure: fail (a)\r\n");
      ret_i = 0;
    }

    c3_free(pri);
    u3z(pro);
  }

  { // cell (dog) test //
    u3_noun non = u3nc(1, 2);
    u3_noun pro = share_foobar(non);

    c3_c* pri = u3m_pretty(pro);
    if ( 0 != strcmp("[[%foo 1 2] %bar 1 2]", pri) ) {
      fprintf(stderr, "structure: fail (b)\r\n");
      ret_i = 0;
    }

    c3_free(pri);
    u3z(pro);
    u3z(non);
  }

  return ret_i;
}

/* main(): run all test cases.
*/
int
main(int argc, char* argv[])
{
  _setup();

  if ( !_test_sharing() ) {
    fprintf(stderr, "test_sharing: failed\r\n");
    exit(1);
  }

  //  GC
  //
  u3m_grab(u3_none);

  fprintf(stderr, "test_sharing: ok\r\n");

  return 0;
}

