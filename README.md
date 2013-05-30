Clean All The Things
====================

This software does not, alas, clean all the things.  However, it is useful
for helping one focus on which items are most in need of cleaning, so that
all the things might be found to be reasonably clean at any given time.

I am a Perl nerd, and I don't expect this software to be used by anyone but
fellow Perl nerds.  You should at least know how to use CPAN to install the
requested modules, although you can safely comment out the block containing
`use Net::Twitter::Lite` if you have no intention of using this app with
Twitter.

This should be considered an alpha release.  Expect falling rocks, etc.


Changes
-------

### 30 May 2013

New command line option "warn" for changing the warning threshold.  Default
value is 80% as before.

Update maintenance logic to include both positive and negative changes.

Include job names when printing maintenance update progress.

Fixed a minor bug where a job with a null timestamp could produce uninitialized
value warnings, by setting a numeric default value of zero.

Fixed a minor bug where exit was needed instead of return, producing a "can't
return outside a subroutine" warning.


### 21 May 2013

Added a new command 'm' to mark a job as completed without having to look
at the full set of prompts to edit the item.

Enforced limits of 45 characters for job names and 60 characters for regions.

Fixed a minor bug where the list would cut off at 21 items instead of 20.

Fixed a minor bug where negative totals were not recognized by the parser.


### 8 May 2013

Initial release.


Overview
--------

This distribution should contain the following files:

- `README.md`    (these instructions)
- `clean_cli.pl` (command line interface)
- `housework.db` (a SQLite database)

Running `clean_cli.pl` will give you command line access to job status and
the ability to add new jobs or edit existing jobs.  It expects `housework.db`
to be in the same directory as itself, so keep them together.

The only other filesystem assumption is the existence of a .ssh directory in
the user's home directory.  If the script is configured to post status updates
to Twitter (more on that later), it will store the access codes as a Storable
hash in `$HOME/.ssh/.cleanthings` with user-read-only (600) permissions.  You
can change this location if you want by editing the value of `$twitter_file`
in `clean_cli.pl`.

In the near future I hope to add a subdirectory of webpages providing a
more generally accessible interface to the database, and I'll probably have
to program it in PHP.  (I'm sorry.)  But you'll still want the command line
script to run out of cron to do regular maintenance on the database, as
described below.


Usage
-----

The `clean_cli.pl` script has two major modes.  Without any options, it will
provide a basic user interface for viewing and editing jobs.  Here's some
example output:

    11 jobs found, sorted by most needed first.

    01: Clean Kitchen Floor                                          (100%)
    02: Clean Bathroom Floor Upstairs                                (70%)
    03: Clean Windowsills and Baseboards                             (70%)
    04: Clean Bathroom Counter Downstairs                            (70%)
    05: Vacuum Carpet Upstairs                                       (65%)
    06: Clean Bathroom Mirrors Upstairs                              (60%)
    07: Clean Bathroom Sink Upstairs                                 (60%)
    08: Clean Bathroom Counter Upstairs                              (50%)
    09: Clean Kitchen Countertops                                    (25%)
    10: Vacuum Carpet Downstairs                                     (10%)
    11: Clean Microwave                                              (0%)

    You may (a)dd a new job, (e)dit an existing job, (m)ark a job completed,
     change the (s)ort order, or (q)uit.

    >

The other major mode is maintenance mode, which is invoked by using the
`--maint` option on the command line.  In maintenance mode, the script will
examine the database, adjust any urgency percentages that need adjusting, print
a status message, and exit.  To have the status message sent to a Twitter
account, run `clean_cli.pl --twitter` and follow the configuration instructions.
This is a one-time configuration option; once configured, Twitter will be
automatically used for all future status updates.

Three other command line options are available.  The `--silent` flag suppresses
all those chatty, helpful status messages and prints only the most essential
output.  (I recommend running `clean_cli.pl --maint --silent` out of cron if
Twitter is being used, to avoid getting any email unless an error occurs.)
Specifying `--warn=<n>` on the command line will let you change the warning
threshold from the default 80% - for example, `--warn=90` will only include
jobs that have reached 90% urgency or higher in the status message returned
when running in maintenance mode.

The other command line option is `--region=<n>` which only comes into play if
you assign your jobs into different numbered regions.  For example, I use
two regions named (1)Upstairs and (2)Downstairs, and I actually have two cron
jobs defined, such that I get notified of Upstairs jobs in the morning and
Downstairs jobs in the afternoon, using `--region=1` and `--region=2`
respectively.  Specifying a region on the command line also filters the list
to show only the jobs in that region, and skips the prompt to choose a region
when adding or editing a job.

All the options can be abbreviated: `-m`, `-t`, `-s`, `-w=<n>`, and `-r=<n>`
will also work.


Defining A Job
--------------

    You may (a)dd a new job, (e)dit an existing job, (m)ark a job completed,
     change the (s)ort order, or (q)uit.

    > a

    Currently defined regions:
      1: Upstairs
      2: Downstairs

    Enter your choice - 1, 2, or 'n' for new region.
    [n]> 2

    You may rename this region, or press RETURN to confirm the current name.
    [Downstairs]>

    New job name (45 char max): Clean Bathroom Mirror Downstairs

    Number of days between updates: 6

    Increment amount [0%]: 10

    Current urgency [0%]: 0

I've already explained regions, and job name should be self-explanatory.
But what about the numbers?  Here's the idea: the urgency is how badly the job
needs to be done, on a scale from 0% (just cleaned) to anything over 100%
(disgusting).  Since your computer can't actually examine your house to see how
dirty things are (or mine can't, at any rate), it does some math based on the
numbers you tell it to use.  Every time you execute the script in maintenance
mode, it looks at the last time the urgency was changed and if it was N or more
days ago (N being '6' in the example above), it adds the increment amount (in
this case, 10%) to the total.  In this fashion the urgency of any given job
will slowly creep back up to 100% at the rate you describe, until you log in
to edit the job back down to 0%.  Negative totals are also supported.  Say you
have a job that says "Buy one (X)" and you find it on sale and buy two, you can
say the current urgency is -100% and it will cope accordingly.  (Behold the
power of math!)


Bugs
----

No known bugs, just features I haven't added yet.  There's currently no way to
delete a job or a region, although you can edit it to be something completely
different.  There's no way to temporarily suspend a job except to edit the
frequency or increment amount to zero, and then set it back to the desired
value when you want it to start running again.

The database ships with two regions predefined, Upstairs and Downstairs.  As I
said above, you can rename them but not delete them from the app.  There's no
way to turn off the region feature if you don't need it; a job is always
attached to a region.  Of course, all things are possible if you want to edit
the script and mess around with sqlite, but you're on your own with that.  :)

There are probably other features that will be obvious to anyone else that I
just haven't thought of because they don't fit my intended usage of the app.
Pull requests are welcome!


License
-------

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.  For more information about the Perl Artistic
License 2.0, visit <http://opensource.org/licenses/artistic-license-2.0>.


Disclaimers
-----------

This software is provided "as is" and any express or implied warranties,
including, but not limited to, the implied warranties of merchantability and
fitness for a particular purpose are disclaimed.

The author of this software is in no way affiliated with the website
[Hyperbole and a Half](http://hyperboleandahalf.blogspot.com/), whose
"This Is Why I'll Never Be An Adult" web comic inspired the name of this
application.


_kareila at dreamwidth dot org // 21 May 2013_
