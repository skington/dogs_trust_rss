#!/usr/bin/env perl

use lib::abs './lib';
use strict;
use DogsTrust::List;

STDOUT->autoflush(1);
for my $centre (qw(gla wc)) {
    print "$centre...";
    my $list = DogsTrust::List->new;
    my @dogs = $list->fetch($centre);
    print scalar @dogs, "\n";
    $list->write_rss($centre, @dogs);
}
