#!/usr/bin/perl

# This module is part of the Clean All The Things project, maintained at
# https://github.com/kareila/clean-all-the-things
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


package SimpleTweet;

use warnings;
use strict;

use Storable;

use Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK);
@ISA = qw(Exporter);
@EXPORT = qw(tweet can_tweet);
@EXPORT_OK = qw(write_config);

my $twitter_file = $ENV{"HOME"} . "/.ssh/.cleanthings";
my @twitter_keys = qw( consumer_key consumer_secret access_token access_token_secret );

use Net::Twitter::Lite::WithAPIv1_1;
# "Install Net::OAuth 0.25 or later for OAuth support"
use Net::OAuth;
# as of Jan 2014 this is required for SSL certs
use Mozilla::CA;


sub write_config {
    my ( $info ) = @_;
    return unless defined $info;
    foreach my $key ( @twitter_keys ) {
        return unless defined $info->{$key};  # verify we have needed info
    }

    Storable::store( $info, $twitter_file ) or return;
    chmod 0600, $twitter_file;
    return $twitter_file;
}

sub read_config {
    return unless -f $twitter_file;
    my $info = Storable::retrieve $twitter_file;
    return unless defined $info;
    $info->{ssl} = 1;
    return $info;
}

sub can_tweet {
    my $info = &read_config;
    return defined $info ? 1 : 0;
}

sub tweet {
    my ( $msg ) = @_;
    return unless length $msg;
    $msg = substr( $msg, 0, 140 );  # truncate tweets longer than 140 chars

    my $info = &read_config;
    return unless defined $info;

    my $nt = Net::Twitter::Lite::WithAPIv1_1->new( %$info );
    eval { $nt->update( $msg ) };
    $@ ? warn "Twitter error: $@\n" : return $msg;
}


1;
