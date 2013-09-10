#!/usr/bin/perl

# This script is part of the Clean All The Things project, maintained at
# https://github.com/kareila/clean-all-the-things
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


use warnings;
use strict;

my $region = 0;  # constrain to a certain region (expects integer id)
my $silent = 0;  # suppress warnings (e.g. when running out of crontab)
my $maint  = 0;  # flag indicating maintenance mode (calculate updates and exit)
my $tconf  = 0;  # flag indicating whether Twitter config info needs to be entered
my $saynum = 80; # start notifying at 80% or more, unless overridden on the CLI

use Getopt::Long;
GetOptions( 'twitter' => \$tconf, 'maint' => \$maint, 'silent' => \$silent,
            'warn=i' => \$saynum, 'region=i' => \$region );

use Storable;
my $skip_twitter = 0;
my $twitter_file = $ENV{"HOME"} . "/.ssh/.cleanthings";
my $twitter_info;

# check for saved Twitter auth info
$twitter_info = Storable::retrieve $twitter_file if -f $twitter_file;

if ( $maint && ! defined $twitter_info ) {
    $skip_twitter = 1;
    warn "No Twitter access information found; will not post status updates.\n"
        unless $silent;
}

use DBI;
my $dbh = DBI->connect( "dbi:SQLite:housework.db" ) || die "Cannot connect: $DBI::errstr";
my ( @jobs, %jobs, %jobtimes, @jobtimes, %regnames );

sub reload_jobs {
    if ( $_[0] ) {  # optionally populates %regnames
        my $reg = $dbh->selectall_arrayref( 'SELECT * FROM regions', { Slice => {} } );
        %regnames = map { $_->{regid} => $_->{regname} } @$reg;
    }

    my $select_jobs = 'SELECT * FROM jobs';
    $select_jobs .= ' WHERE regid=?' if $region;
    $select_jobs .= ' ORDER BY currtotal DESC';
    my @sel_job_args = ( $select_jobs, { Slice => {} } );
    push @sel_job_args, $region if $region;

    @jobs = @{ $dbh->selectall_arrayref( @sel_job_args ) };
    return unless @jobs;  # nothing else will turn up anything useful
    %jobs = map { $_->{jobid} => $_ } @jobs;

# in maintenance mode, we care about the last time the urgency was changed.
# in user mode, we care about the last time the urgency was decremented (work done).

    my $select_timelog = 'SELECT MAX(timestamp) FROM timelog WHERE jobid=? AND percent';
    $select_timelog .= $maint ? '!=0' : '<=0';

    foreach my $job ( @jobs ) {
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

    @jobtimes = sort { $a->{timestamp} <=> $b->{timestamp} } values %jobtimes;

    # this populates the global job variables; nothing to return
}

&reload_jobs(!$maint);

if ( $maint ) {
    exit 0 unless @jobs;  # nothing to do
    my %updated;

    # update urgencies as needed
    foreach my $id ( keys %jobs ) {
        my $jdata = $jobs{$id};
        my $tdata = $jobtimes{$id};
        next unless $jdata->{frequency} > 0;
        next unless $jdata->{urgency};

        # plus or minus five minutes...
        if ( time > $jdata->{frequency} * 86100 + $tdata->{timestamp} ) {
            $updated{$id} = $jdata->{currtotal} + $jdata->{urgency};
            $dbh->do( 'UPDATE jobs SET currtotal=? WHERE jobid=?',
                      undef, $updated{$id}, $id );
            $dbh->do( 'INSERT INTO timelog (jobid, timestamp, percent)' .
                      ' VALUES (?,?,?)', undef, $id, time, $jdata->{urgency} );

        }
    }

    if ( %updated ) {
        &reload_jobs();
        unless ( $silent ) {
            foreach my $j ( keys %updated ) {
                warn sprintf( "Job #%d updated to %d%% needed. (%s)\n",
                              $j, $updated{$j}, $jobs{$j}->{jobname} );
            }
            warn "\n";
        }

        # figure out top two or three most urgent jobs & notify
        my @j = grep { $_->{currtotal} >= $saynum } @jobs;
        exit 0 unless @j;  # nothing urgent

        my $twitter_status = '';
        foreach (0..1) {
            next unless defined $j[$_];
            $twitter_status .= $j[$_]->{jobname} . ' (';
            $twitter_status .= $j[$_]->{currtotal} . '%) ';
        }
        my $rem = scalar @j - 2;
        $twitter_status .= "+$rem more" if $rem > 0;
        chomp $twitter_status;

        if ( $twitter_status && ! $skip_twitter ) {
            warn "Posting to Twitter using stored credentials.\n"
                unless $silent;
            use Net::Twitter::Lite::WithAPIv1_1;
            # "Install Net::OAuth 0.25 or later for OAuth support"
            use Net::OAuth;
            my $nt = Net::Twitter::Lite::WithAPIv1_1->new( %$twitter_info );
            eval { $nt->update( $twitter_status ) };
            warn "Twitter error: $@\n" if $@;
        }

        warn "$twitter_status\n" unless $silent;

    } else {
        warn "No updates.\n" unless $silent;
    }

    exit 0;
}

# if we haven't exited by now, we wanted to run in user mode.

use Term::ReadLine;
my $term = new Term::ReadLine;

warn "Welcome to the Clean All The Things configuration interface.\n\n" .
     "To run this script in maintenance mode, which notes the current time and\n" .
     " posts a cleanup list to Twitter (if enabled), use the --maint option.\n\n"
    unless $silent;

if ( $tconf ) {
    warn "Please enter your consumer key and access token below.\n" .
         "If you don't have these, you will need to register on dev.twitter.com.\n" .
         "Refer to http://dft.ba/-5AhL for more information.\n\n" unless $silent;
    warn "WARNING: cached Twitter tokens were found!!!\n" .
         "Proceed only if you wish to enter new tokens!\n" .
         "Otherwise, rerun this script without the --twitter option.\n\n" if $twitter_info;

    # prompt for Twitter information
    foreach my $key ( qw( consumer_key consumer_secret access_token access_token_secret ) ) {
        my $prompt = ucfirst "$key: "; $prompt =~ s/_/ /;
        $twitter_info->{$key} = $term->readline($prompt);
        chomp $twitter_info->{$key};
        exit 0 unless length $twitter_info->{$key};
    }
    Storable::store $twitter_info, $twitter_file;
    chmod 0600, $twitter_file;
    warn "Twitter information stored in $twitter_file\n\n" unless $silent;
}

unless ( -f $twitter_file ) {
    warn "No Twitter access info found; please rerun with --twitter option to configure.\n\n"
        unless $silent;
}

# enough about Twitter configuration, let's manage jobs.

use POSIX qw( strftime );

my $limit = 20;
my $jsort = 0;
my %jsort = ( '0' => 'most needed', '1' => 'least recent' );

&print_status;

sub print_status {
    warn "More than $limit matching jobs found; only displaying top $limit.\n"
        if !$silent and scalar @jobs > $limit;
    printf "%d jobs found, sorted by %s first.\n\n", scalar @jobs, $jsort{$jsort};
    my @print_jobs = $jsort ? @jobtimes : @jobs;
    my $i = 1;
    foreach my $j ( @print_jobs ) {
        my $id = $j->{jobid};
        my $stat = $jsort ? strftime( "%D", localtime( $jobtimes{$id}->{timestamp} ) )
                          : $j->{currtotal} . '%';
        printf "%02d: %-60s (%s)\n", $i, $jobs{$id}->{jobname}, $stat;
        last if ++$i > $limit;
    }
    print "\n";
    &main_prompt();
}

sub main_prompt {
    print "You may (a)dd a new job, (e)dit an existing job, (m)ark a job completed,\n change the (s)ort order, or (q)uit.\n\n";
    my $input = &print_prompt();
    &parse_input($input);
}

sub print_prompt {
    my $prompt = defined $_[0] && length $_[0] ? $_[0] : "> ";
    my $input = $term->readline($prompt);
    chomp $input;
    print "\n";
    return $input;
}

sub parse_input {
    my $input = $_[0];
    my ($c, @args) = split /\s+/, $input;
    return &main_prompt() unless defined $c and length $c;

    if ( $c =~ /^s/ ) { # change the sort order
        $jsort = $jsort ? 0 : 1;
        return &print_status;
    } elsif ( $c =~ /^q/ ) {
        exit 0;
    } elsif ( $c =~ /^a/ ) {
        return &prompt_add();
    } elsif ( $c =~ /^e/ ) {
        return &prompt_edit( @args );
    } elsif ( $c =~ /^m/ ) {
        return &prompt_edit( @args, 0 );
    } else {
        print "Sorry, I don't know what you mean by that.\n";
        return &main_prompt();
    }
}

sub prompt_edit {
    my @args = @_;
    unless ( @args && $args[0] ) {
        print "Please type the number of the job you wish to edit.\n\n";
        my $input = &print_prompt();
        @args = ( $input, $args[0] );
    }
    my $j = $args[0];
    exit 0 if $j eq 'q';
    my @print_jobs = $jsort ? @jobtimes : @jobs;
    my $job = $print_jobs[$j-1];
    if ( $j !~ /^\d+$/ or $j > $limit or $j < 1 or ! $job->{jobid} ) {
        print "Sorry, I can't find that job.\n";
        return &main_prompt();
    }
    &show_details( $job->{jobid} );

    my $p = $args[1];
    if ( defined $p and $p =~ /^-?\d+$/ ) {
        my $delta = 0;
        $delta = $p - $job->{currtotal} if defined $job->{currtotal};
        my $continue = &print_prompt( "Reset the urgency of this job to $p%? [Y/N] > " );
        if ( $continue && $continue =~ /^y/i ) {
            $dbh->do( 'UPDATE jobs SET currtotal=? WHERE jobid=?',
                      undef, $p, $job->{jobid} );
            $dbh->do( 'INSERT INTO timelog (jobid, timestamp, percent)' .
                      ' VALUES (?,?,?)', undef, $job->{jobid}, time, $delta );
            &reload_jobs();
        }
    } else {
        my $continue = &print_prompt( 'Enter new data for this job? [Y/N] > ' );
        return &prompt_add( $job->{jobid} ) if $continue && $continue =~ /^y/i;
    }
    &print_status;
}

sub show_details {
    my ( $jobid ) = @_;
    return unless $jobid;
    my $jdata = $jobs{$jobid};
    my $tdata = $jobtimes{$jobid};
    my $region = $regnames{$jdata->{regid}} . ' (#' . $jdata->{regid} . ')';

    my @lines = (
                 [ 'Job Name', $jdata->{jobname} ],
                 [ 'Region Name', $region ],
                 [ 'Number of days between urgency updates', $jdata->{frequency} ],
                 [ 'Amount to increment urgency on each update' , $jdata->{urgency} . '%' ],
                 [ 'Current urgency', ( $jdata->{currtotal} || 0 ) . '%' ],
                 [ 'Last worked on', strftime( "%D", localtime( $tdata->{timestamp} ) ) ]
                );

    foreach ( @lines ) {
        printf "%s: %s\n", $_->[0], $_->[1];
    }
    print "\n";
}

sub prompt_add {
    my ( $jobid ) = @_;
    my $jdata = defined $jobid ? $jobs{$jobid} : {};

    my $regid = &prompt_region( $jdata->{regid} );

    my $append = sub { $_[0] . ( $_[1] ? " \[$_[1]\]" : '' ) . ': ' };

    my $jobname = &print_prompt( $append->( "New job name (45 char max)", $jdata->{jobname} ) );
    $jobname = $jdata->{jobname} unless length $jobname;
    return &main_prompt() unless $jobname;
    $jobname = substr( $jobname, 0, 45 );  # truncate names longer than 45 chars

    my $freq = &print_prompt( $append->( "Number of days between updates", $jdata->{frequency} ) );
    $freq = $jdata->{frequency} || 0 unless length $freq;

    my $urg = &print_prompt( $append->( "Increment amount", ( $jdata->{urgency} || 0 ) . '%' ) );
    $urg = $jdata->{urgency} || 0 unless length $urg;
    $urg =~ s/%$// if defined $urg;

    my $curr = &print_prompt( $append->( "Current urgency", ( $jdata->{currtotal} || 0 ) . '%' ) );
    $curr = $jdata->{currtotal} || 0 unless length $curr;
    $curr =~ s/%$// if defined $curr;

    my @lines = (
                 [ 'Job Name', $jobname ],
                 [ 'Region Name', $regnames{$regid} . ' (#' . $regid . ')' ],
                 [ 'Number of days between urgency updates', $freq ],
                 [ 'Amount to increment urgency on each update' , $urg . '%' ],
                 [ 'Current urgency', $curr . '%' ],
                );

    foreach ( @lines ) {
        printf "%s: %s\n", $_->[0], $_->[1];
    }
    print "\nIf everything is correct, press Y to continue, or N to abort changes.\n";
    my $continue = &print_prompt( 'Is everything correct? [Y/N] > ' );
    return &main_prompt() if $continue && $continue =~ /^n/i;

    if ( defined $jobid ) {
        $dbh->do( 'UPDATE jobs SET jobname=?, frequency=?, urgency=?, regid=?, currtotal=?' .
                  ' WHERE jobid=?', undef, $jobname, $freq, $urg, $regid, $curr, $jobid );

    } elsif ( $jobname && $freq =~ /^\d+$/ && $urg =~ /^\d+$/ && $curr =~ /^-?\d+$/ ) {
        $dbh->do( 'INSERT INTO jobs (jobname, frequency, urgency, regid, currtotal)' .
                  ' VALUES (?,?,?,?,?)', undef, $jobname, $freq, $urg, $regid, $curr );
        ( $jobid ) = $dbh->selectrow_array( 'SELECT jobid FROM jobs WHERE jobname=?',
                                            undef, $jobname );
    }

    if ( $jobid ) {
        my $percent = 0;
        $percent = $curr - $jdata->{currtotal} if defined $jdata->{currtotal};
        $dbh->do( 'INSERT INTO timelog (jobid, timestamp, percent)' .
                  ' VALUES (?,?,?)', undef, $jobid, time, $percent );
        &reload_jobs();
        return &print_status;
    }

    # figure out what went wrong
    warn "Could not save job: no job name given.\n" unless $jobname;
    warn "Could not save job: invalid frequency.\n" if $freq !~ /^\d+$/;
    warn "Could not save job: invalid urgency.\n" if $urg !~ /^\d+$/;
    warn "Could not save job: invalid current total.\n" if $curr !~ /^-?\d+$/;
    &main_prompt();
}

sub prompt_region {
    my ( $regid ) = @_;
    my $regp = $regid // 'n';

    return $regid || $region if $region and $regnames{$region}; # constrained

    print "Currently defined regions:\n";
    my $rlist = 'Enter your choice -';
    foreach my $r ( sort keys %regnames ) {
        printf " %2s: %s\n", $r, $regnames{$r};
        $rlist .= " $r,";
    }
    print "\n$rlist or 'n' for new region.\n";
    my $regsel = &print_prompt( "[$regp]> " ) || $regp;

    if ( $regsel =~ /^n/i ) {
        my $newreg = &print_prompt( "New region name: " );
        unless ( &is_unique_regname( $newreg ) ) {
            print "There is already a region with that name.\n\n";
            return &prompt_region( @_ );
        }
        if ( length $newreg > 60 ) {
            print "Region names should not be longer than 60 characters.\n\n";
            return &prompt_region( @_ );
        }
        $dbh->do( 'INSERT INTO regions (regname) VALUES (?)', undef, $newreg );
        # update %regnames
        my $reg = $dbh->selectall_arrayref( 'SELECT * FROM regions', { Slice => {} } );
        %regnames = map { $_->{regid} => $_->{regname} } @$reg;
        my %regids = map { $_->{regname} => $_->{regid} } @$reg;
        return $regids{$newreg};

    } elsif ( $regnames{$regsel} ) {
        return &rename_region( $regsel );
    } else {
        print "That is not a valid region ID.\n\n";
        &prompt_region( @_ );
    }
}

sub rename_region {
    my ( $regid ) = @_;
    return unless defined $regid;

    print "You may rename this region, or press RETURN to confirm the current name.\n";
    my $newname = &print_prompt( "[$regnames{$regid}]> " );
    if ( defined $newname and length $newname ) {
        unless ( &is_unique_regname( $newname ) || lc $newname eq lc $regnames{$regid} ) {
            print "There is already a region with that name.\n\n";
            return &rename_region( @_ );
        }
        if ( length $newname > 60 ) {
            print "Region names should not be longer than 60 characters.\n\n";
            return &rename_region( @_ );
        }
        $dbh->do( 'UPDATE regions SET regname=? WHERE regid=?', undef, $newname, $regid );
        # update %regnames
        $regnames{$regid} = $newname;
    } else {
        return $regid;
    }
    # keep prompting until they accept the name
    &rename_region( @_ );
}

sub is_unique_regname {
    my ( $reg ) = @_;
    return unless defined $reg and length $reg;

    my %regids = map { lc $regnames{$_} => $_ } keys %regnames;
    return $regids{lc $reg} ? 0 : 1;
}
