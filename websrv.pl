#!/usr/bin/perl

# This script is part of the Clean All The Things project, maintained at
# https://github.com/kareila/clean-all-the-things
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


use warnings;
use strict;

use Dancer;
use Template;

set template => 'template_toolkit';
set logger   => 'console';
set log      => 'warning';

use lib '.';
use CleanDB;
use SimpleTweet;

# uncomment the line below to turn off Twitter posting
# sub can_tweet { return 0 }  # <--- falls through to SimpleTweet if omitted
# uncomment the line above to turn off Twitter posting

any ['get', 'post'] => '/' => sub {
    # locally scoping $dbi here should release the file lock on
    # the database after the page is rendered
    my $dbi = CleanDB->new( 'housework.db' );
    $dbi->db_load();
    $dbi->region_load();
    my %regnames = $dbi->regions_by_name;
    my %regions = map { $_->{jobid} => $regnames{ $_->{regid} } }
                      $dbi->jobs_as_list;

    my $regview = params->{"show"};
    $regview = '' unless $regview && $regnames{$regview};

    my @messages;

    if ( request->method() eq "POST" ) {
        my ( %changes, %deltas, %unsynced );

        foreach my $job ( $dbi->jobs_as_list ) {
            my $id = $job->{jobid};
            my $currval = $job->{currtotal} // 0;
            my $oldval = params->{"prev_$id"};
            my $newval = params->{"curr_$id"};
            next unless defined $newval;

            if ( $newval ne $oldval and $newval =~ /^-?\d+$/ ) {
                $unsynced{$id} = $currval if $oldval ne $currval;
                $changes{$id} = $newval + 0;
                $deltas{$id} = $newval - $currval;
            }
        }

        if ( %unsynced ) {
            return template 'confirm.tt', {
                title    => "Confirm Changes",
                regview  => $regview,
                jobhash  => { $dbi->jobs_as_hash },
                regions  => \%regions,
                changes  => \%changes,
                unsynced => \%unsynced,
            };
        }

        my $status_msg = sub {
            my ( $job, $changed ) = @_;
            return unless defined $changed;
            my $msg = '';
            $msg = '[' . $regnames{ $job->{regid} } . '] ' if $job->{regid};
            $msg .= $job->{jobname} . " changed from ";
            $msg .= $job->{currtotal} // 0;
            $msg .= "% to " . $changed . "%.";
            return $msg;
        };

        foreach my $job ( $dbi->jobs_as_list ) {
            next unless exists $changes{ $job->{jobid} };
            push @messages, $status_msg->( $job, $changes{ $job->{jobid} } );
        }

        if ( can_tweet() ) {
            SimpleTweet::tweet( $_ ) foreach @messages;
        }

        foreach my $id ( keys %changes ) {
            $dbi->job_update_total( $id, $changes{$id} );
            $dbi->job_timelog( $id, $deltas{$id} );
            warn "Updated job #$id\n" if setting('log') eq 'debug';
        }

        $dbi->db_load() if %changes;
    }

    # filter by desired region if needed
    my @joblist = $dbi->jobs_as_list;
    @joblist = grep { $_->{regid} == $regview } @joblist if $regview;

    template 'index.tt', {
        title   => "Clean All The Things!",
        regview => $regview,
        joblist => \@joblist,
        regions  => \%regions,
        regnames => \%regnames,
        messages => @messages ? \@messages : undef,
    };
};

start;    # listens on http://localhost:3000/ by default
