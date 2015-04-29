use strict;
use warnings;
use Test::More;

BEGIN: {
unless (use_ok('Honeydew-Queue')) {
BAIL_OUT("Couldn't load Honeydew-Queue");
exit;
}
}



done_testing;
