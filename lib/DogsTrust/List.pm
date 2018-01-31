package DogsTrust::List;

use Moose;
use strict;
use warnings;
use feature 'signatures';
no warnings 'uninitialized';
no warnings 'experimental::signatures';

use HTML::TreeBuilder;
use LWP;
use XML::RSS::SimpleGen;

=head1 NAME

DogsTrust::List - a list of Dogs Trust dogs

=head1 SYNOPSIS

 my $list = DogsTrust::List->new;
 my @dogs = $list->fetch('Glasgow');
 ...

=head1 DESCRIPTION

A DogsTrust::List object knows how to fetch lists of dogs from the
Dogs Trust website.

=head2 Attributes

=head3 user_agent

An LWP::UserAgent object that can fetch web pages.

=cut

has 'user_agent' => (
    is      => 'rw',
    isa     => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new(agent => 'DogsTrustRSS') }
);

=head2 fetch

 In: $centre
 Out: @dogs

Supplied with the name of a centre (e.g. C<gla> or C<wc>), retrieves the web
page(s) for the specified centre, and returns a list of dogs at that centre.

=cut

my $url_base = 'https://www.dogstrust.org.uk';

sub fetch ($self, $centre) {
    my @dogs;

    # Start at the main page for this centre.
    my $url_list = $self->_url_list($centre);

    # Go through each page in turn.
    page:
    while ($url_list) {
        # Fetch the web page in question, and parse it.
        my $response = $self->user_agent->get($url_list);
        die $response->decoded_content if !$response->is_success;
        my $tree
            = HTML::TreeBuilder->new_from_content($response->decoded_content);

        # Look for links to dogs.
        my @links = $tree->look_down(_tag => 'a', class => 'grid__element');
        for my $link (@links) {
            my $dog = $self->_parse_link_contents($link);
            push @dogs, $dog unless $self->dog_unacceptable($dog);
        }

        # If there's a "next page" link, follow it.
        if (
            my $next_page_link = $tree->look_down(
                _tag => 'a',
                rel  => 'next'
            )
            )
        {
            my $relative_url = $next_page_link->attr('href');
            $url_list =~ s{ ( https?:// [^/]+ ) / (.+) }{$1$relative_url}x;
        } else {
            last page;
        }
    }
    # Return what we found.
    return @dogs;
}

sub _url_list ($self, $centre) {
    sprintf('%s/rehoming/dogs/filters/%s~~~~~n~', $url_base, lc $centre);
}

sub _url_dog ($self, $dog_id) {
    sprintf('%s/rehoming/dogs/dog/%s', $url_base, $dog_id);
}

sub _parse_link_contents ($self, $link) {
    my $dog = { id => $link->attr('href') =~ m{/filters/ [^/]+ / (\d+) }x, };
    for ([name => 'h3'], [breed => 'span']) {
        my ($field, $tag) = @$_;
        $dog->{$field}
            = ($link->look_down(_tag => $tag)->content_list)[0]
            =~ s/^\s+//gr =~ s/\s+$//gr;
    }

    # Fetch that dog's page in turn.
    my $response_dog = $self->user_agent->get($self->_url_dog($dog->{id}));
    my $tree_dog
        = HTML::TreeBuilder->new_from_content($response_dog->decoded_content);
    eval {
    my @paragraphs
        = map { $_->content_list }
        $tree_dog->look_down(_tag => 'div', class => 'panel-body')
        ->look_down(_tag => 'p');
    $dog->{description} = \@paragraphs;
    1;
} or do {
    $DB::single = 1;
    1;
};
    return $dog;
}

sub dog_unacceptable ($self, $dog) {
    # Can't be an only dog or only pet
    return 1 if grep { /only \s (dog|pet)/xi } @{$dog->{description}};

    # No beagles, border collies, or tiny yappy things.
    return 1 if $dog->{breed} =~ / ( beagle | chihuahua ) /xi
        || ($dog->{breed} =~ /border/i && $dog->{breed} =~ /collie/i);
    
    # No muzzles.
    return 1 if grep { /muzzled/i } @{ $dog->{description} };

    # Nothing immediately wrong.
    return 0;
}

=head2 write_rss

 In: $centre
 In: @dogs

Supplied with a centre name and a list of dogs(e . g . from L <fetch>), writes
it out as an RSS feed .

=cut

sub write_rss ($self, $centre, @dogs) {
    my $rss = XML::RSS::SimpleGen->new($self->_url_list($centre),
        'Dogs Trust: ' . $centre);
    for my $dog (sort { $a->{id} <=> $b->{id} } @dogs) {
        $rss->item(
            $self->_url_dog($dog->{id}),
            $dog->{breed} . ': ' . $dog->{name},
            \('<p>' . join('</p><p>', @{ $dog->{description} }) . '</p>')
        );
    }
    $rss->save(lib::abs::path("../../feed-$centre.rss"));
}

__PACKAGE__->meta->make_immutable;
1;

