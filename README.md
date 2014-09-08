Clean All The Things
====================

This software does not, alas, clean all the things.  However, it is useful
for helping one focus on which items are most in need of attention, so that
all the things might be found to be reasonably clean at any given time.

I am a Perl nerd, and I don't expect this software to be used by anyone but
fellow Perl nerds.  You should at least know how to use CPAN to install the
requested modules, although many of the ones requested by `SimpleTweet.pm` can
be safely commented out if you have no intention of using this app with Twitter.

This should be considered a beta release.  I've been using this software for
several months and the core features are pretty much set, but there is always
room for improvement and further refinement.


Changes
-------

### 8 Sep 2014

Added a new section above the tabs on the web interface which will print
out the status messages when changes are submitted (in addition to posting
them on Twitter), for better user feedback.


### 12 Mar 2014

New `SimpleTweet.pm` module encapsulates basic Twitter functionality and
shares it with the command line script as well as the web server.  Both
interfaces now tweet when the status of a job is manually changed, in
addition to the periodic maintenance reminders as before.

Tabs for viewing tasks assigned to a specific region have been added to
the web interface.  A new `public/` subdirectory holds the relevant CSS file.


### 23 Jan 2014

Twitter now requires SSL connections to be used.  Relies on the Mozilla::CA
module for certificate authority, which should be included automatically
when the other Twitter-related modules are installed.


### 11 Nov 2013

Print region names in addition to job names when viewing all regions, to
avoid confusion with similarly named jobs assigned to different regions.
This may cause display width issues with very long names when using the CLI
interface; I don't anticipate such problems when using the web interface.


### 26 Sep 2013

Includes a simple web service for updating percentages.  To get it working,
just run `websrv.pl` and point your browser at localhost:3000.  You will need
to install the Dancer and Template modules from CPAN if you don't already have
them.  The new `views/` subdirectory contains the page templates.


### 13 Sep 2013

Added a new command 'r' to manage region names (add/delete/rename).

Refactored database subroutines into a separate module to share code with
a planned web interface.

Added an option to the job edit workflow to allow job deletion.

Removed single characters (e.g. Y/N confirmation prompts) from command history.


### 12 Jun 2013

Changed module from Net::Twitter::Lite to Net::Twitter::Lite::WithAPIv1_1,
because Twitter turned off their 1.0 API.


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

Initial release of `clean_cli.pl`.


Overview
--------

This distribution should contain the following files:

- `CleanDB.pm`     (code module that interfaces with the database)
- `README.md`      (these instructions)
- `SimpleTweet.pm` (code module that interfaces with Twitter)
- `clean_cli.pl`   (command line interface)
- `housework.db`   (a SQLite database)
- `public/`        (subdirectory for CSS files and web images)
- `views/`         (subdirectory for web page templates)
- `websrv.pl`      (server for web interface)

Running `clean_cli.pl` will give you command line access to job status and
the ability to add new jobs or edit existing jobs.  It expects `housework.db`
and `CleanDB.pm` to be in the same directory as itself, so keep them together.
Running `websrv.pl` will start a daemon which listens for HTTP connections
on port 3000 and responds with a simple form for editing job percentages.

The only other filesystem assumption is the existence of a .ssh directory in
the user's home directory.  If the script is configured to post status updates
to Twitter (more on that later), it will store the access codes as a Storable
hash in `$HOME/.ssh/.cleanthings` with user-read-only (600) permissions.  You
can change this location if you want by editing the value of `$twitter_file`
in `SimpleTweet.pm`.

Even if you primarily interact with the database through the web interface,
you'll still want the command line script to run out of cron to do regular
maintenance on the database, as described below.


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
     change the (s)ort order, modify a (r)egion, or (q)uit.

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
when adding or editing a job.  If you don't want to assign jobs to different
areas, you might want to use this option to assign tasks to different members
of your household.  There's no way to turn off the region feature completely;
deleting all the regions will leave all jobs assigned to a single region named
`*UNASSIGNED*`.  The database ships with two regions predefined, which are
Upstairs and Downstairs.

All the options can be abbreviated: `-m`, `-t`, `-s`, `-w=<n>`, and `-r=<n>`
will also work.


Defining A Job
--------------

    You may (a)dd a new job, (e)dit an existing job, (m)ark a job completed,
     change the (s)ort order, modify a (r)egion, or (q)uit.

    > a

    Currently defined regions:
      1: Upstairs
      2: Downstairs

    Enter your choice - 1, 2, or 'n' for new region.
    [n]> 2

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

No known bugs, just features I haven't added yet.  There's no way to temporarily
suspend a job except to edit the frequency or increment amount to zero, and then
set it back to the desired value when you want it to start running again.

The web interface is very basic.  I included some simple checks for concurrent
access, but it is not protected by any sort of user authentication.  You should
still use the command line interface to add, delete, or edit job details.  Also,
the CLI script will still need to be scheduled to run in maintenance mode to
keep job statuses up to date, even if using the web interface exclusively for
monitoring and updating tasks.

I believe that the command line script assumes exclusive database access, and
will need to be updated to avoid concurrency issues if another user accesses
the database via the web at the same time.  To avoid unpleasant surprises, I
would recommend suspending `websrv.pl` while using `clean_cli.pl`.

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


_kareila at dreamwidth dot org // 8 Sep 2014_
