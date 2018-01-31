#!/usr/bin/env perl
# Check that we can fetch lists of dogs.

use strict;
use warnings;

use Test::More;

use_ok('DogsTrust::List');

my $list = DogsTrust::List->new;
my @dogs = $list->fetch('gla');
$DB::single = 1;
1;

done_testing();
