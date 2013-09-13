#!/usr/bin/perl

# This module is part of the Clean All The Things project, maintained at
# https://github.com/kareila/clean-all-the-things
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


package CleanDB;

use warnings;
use strict;

use DBI;

sub new {
	my ( $class, $dbfile ) = @_;
	die "Database error: file not found" unless defined $dbfile && -f $dbfile;
	my $dbh = DBI->connect( "dbi:SQLite:$dbfile" ) || die "Cannot connect: $DBI::errstr";
	my $self = { db => $dbh };
	bless $self, ( ref $class ? ref $class : $class );
	return $self;
}

sub region_load {
	my ( $self ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	$self->{regions} = $dbh->selectall_arrayref( 'SELECT * FROM regions', { Slice => {} } );
}

sub db_load {
	my ( $self, %opts ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	my ( $region, $maint )  = ( $opts{region}, $opts{maint} );

    my $select_jobs = 'SELECT * FROM jobs';
    $select_jobs .= ' WHERE regid=?' if $region;
    $select_jobs .= ' ORDER BY currtotal DESC';
    my @sel_job_args = ( $select_jobs, { Slice => {} } );
    push @sel_job_args, $region if $region;

    my $jobs = $dbh->selectall_arrayref( @sel_job_args );
    return unless @$jobs;  # nothing else will turn up anything useful
    $self->{jobs} = $jobs;

# in maintenance mode, we care about the last time the urgency was changed.
# in user mode, we care about the last time the urgency was decremented (work done).

    my $select_timelog = 'SELECT MAX(timestamp) FROM timelog WHERE jobid=? AND percent';
    $select_timelog .= $maint ? '!=0' : '<=0';

    my %jobtimes;

    foreach my $job ( @$jobs ) {
        my $jobid = $job->{jobid} or die 'No jobid found!';
        my @latest = $dbh->selectrow_array( $select_timelog, undef, $jobid );
        if ( $latest[0] ) {
            my $last = $dbh->selectall_arrayref( 'SELECT * FROM timelog WHERE jobid=?'
                       . ' AND timestamp=?', { Slice => {} }, $jobid, $latest[0] );
            @latest = @$last;
        }
        $jobtimes{$jobid} = $latest[0];
        $jobtimes{$jobid}->{timestamp} = 0 unless $jobtimes{$jobid}->{timestamp};
    }

	$self->{jobtimes} = \%jobtimes;

    # this populates the global job variables; nothing to return
}

sub jobs_as_list {
	my ( $self ) = @_;
	my $jobs = $self->{jobs};
	return unless defined $jobs and @$jobs;
	return @$jobs;
}

sub jobs_as_hash {
	my ( $self ) = @_;
	my $jobs = $self->{jobs};
	return unless defined $jobs and @$jobs;
	return map { $_->{jobid} => $_ } @$jobs;
}

sub jobtimes_as_list {
	my ( $self ) = @_;
	my $jobtimes = $self->{jobtimes};
	return unless defined $jobtimes and %$jobtimes;
	return sort { $a->{timestamp} <=> $b->{timestamp} } values %$jobtimes;
}

sub jobtimes_as_hash {
	my ( $self ) = @_;
	my $jobtimes = $self->{jobtimes};
	return unless defined $jobtimes and %$jobtimes;
	return %$jobtimes;
}

sub regions_by_name {
	my ( $self ) = @_;
	my $reg = $self->{regions};
	return unless defined $reg and @$reg;
	push @$reg, { regid => 0, regname => '*UNASSIGNED*' };
    return map { $_->{regid} => $_->{regname} } @$reg;  # %regnames
}

sub regions_by_id {
	my ( $self ) = @_;
	my $reg = $self->{regions};
	return unless defined $reg and @$reg;
    return map { $_->{regname} => $_->{regid} } @$reg;  # %regids
}

sub region_new {
	my ( $self, $name ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	$dbh->do( 'INSERT INTO regions (regname) VALUES (?)', undef, $name );
}

sub region_rename {
	my ( $self, $id, $name ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	$dbh->do( 'UPDATE regions SET regname=? WHERE regid=?', undef, $name, $id );
}

sub region_delete {
	my ( $self, $oldid, $newid ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	$dbh->do( 'DELETE FROM regions WHERE regid=?', undef, $oldid );
	$newid ||= 0;
	$dbh->do( 'UPDATE jobs SET regid=? WHERE regid=?',
			  undef, $newid, $oldid );
}

sub job_update_total {
	my ( $self, $id, $currtotal ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	$dbh->do( 'UPDATE jobs SET currtotal=? WHERE jobid=?',
			  undef, $currtotal, $id );
}

sub job_timelog {
	my ( $self, $id, $percent ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	$dbh->do( 'INSERT INTO timelog (jobid, timestamp, percent)' .
			  ' VALUES (?,?,?)', undef, $id, time, $percent );
}

sub job_delete {
	my ( $self, $id ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	$dbh->do( 'DELETE FROM timelog WHERE jobid=?', undef, $id );
	$dbh->do( 'DELETE FROM jobs WHERE jobid=?', undef, $id );
}

sub job_redefine {
	my ( $self, $jobid, %data ) = @_;
	my $dbh = $self->{db} or die "Database error: DBI handle not found";
	my $warn = sub { warn "Could not save job: $_[0].\n"; return 1 };

	my $regid = $data{regid};
    $regid += 0;  # assign to the "UNASSIGNED" region by default

	my $jobname = $data{jobname};
    $warn->( "no job name given" ) and return unless $jobname;

    my $freq = $data{frequency} // '';
    $warn->( "invalid frequency" ) and return if $freq !~ /^\d+$/;

    my $urg = $data{urgency} // '';
    $warn->( "invalid urgency" ) and return if $urg !~ /^\d+$/;

    my $curr = $data{currtotal} // '';
    $warn->( "invalid current total" ) and return if $curr !~ /^-?\d+$/;

    if ( defined $jobid ) {
        $dbh->do( 'UPDATE jobs SET jobname=?, frequency=?, urgency=?, regid=?, currtotal=?' .
                  ' WHERE jobid=?', undef, $jobname, $freq, $urg, $regid, $curr, $jobid );
    } else {
        $dbh->do( 'INSERT INTO jobs (jobname, frequency, urgency, regid, currtotal)' .
                  ' VALUES (?,?,?,?,?)', undef, $jobname, $freq, $urg, $regid, $curr );
        ( $jobid ) = $dbh->selectrow_array( 'SELECT jobid FROM jobs WHERE jobname=?',
                                            undef, $jobname );
    }

    return $jobid;
}


1;
