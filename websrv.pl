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

any ['get', 'post'] => '/' => sub {
    # locally scoping $dbi here should release the file lock on
    # the database after the page is rendered
    my $dbi = CleanDB->new( 'housework.db' );
    $dbi->db_load();

    if ( request->method() eq "POST" ) {
        my ( %changes, %deltas, %unsynced );

        foreach my $job ( $dbi->jobs_as_list ) {
            my $id = $job->{jobid};
            my $currval = $job->{currtotal};
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
                jobhash  => { $dbi->jobs_as_hash },
                changes  => \%changes,
                unsynced => \%unsynced,
            };
        }

        foreach my $id ( keys %changes ) {
            $dbi->job_update_total( $id, $changes{$id} );
            $dbi->job_timelog( $id, $deltas{$id} );
            warn "Updated job #$id\n" if setting('log') eq 'debug';
        }

        $dbi->db_load() if %changes;
    }

    template 'index.tt', {
        title   => "Clean All The Things!",
        joblist => [ $dbi->jobs_as_list ],
    };
};

start;    # listens on http://localhost:3000/ by default
