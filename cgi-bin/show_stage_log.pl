#!/usr/bin/perl

=comment

Copyright (c) 2003-2010, Andrew Dunstan

See accompanying License file for license details

=cut

use strict;
use warnings;

use DBI;
use Template;
use CGI;
use File::Temp qw(tempfile);

use vars qw($dbhost $dbname $dbuser $dbpass $dbport @log_file_names);

$ENV{BFConfDir} ||= $ENV{BFCONFDIR} if exists $ENV{BFCONFDIR};

require "$ENV{BFConfDir}/BuildFarmWeb.pl";

#require "BuildFarmWeb.pl";

die "no dbname" unless $dbname;
die "no dbuser" unless $dbuser;

my $dsn = "dbi:Pg:dbname=$dbname";
$dsn .= ";host=$dbhost" if $dbhost;
$dsn .= ";port=$dbport" if $dbport;

my $query = CGI->new;

my $system = $query->param('nm');
$system =~ s/[^a-zA-Z0-9_ -]//g if $system;
my $logdate = $query->param('dt');
$logdate =~ s/[^a-zA-Z0-9:_ -]//g if $logdate;
my $stage = $query->param('stg');
$stage =~ s/[^a-zA-Z0-9._ -]//g if $stage;
my $brnch = $query->param('branch') || 'HEAD';
$brnch =~ s{[^a-zA-Z0-9._/ -]}{}g;

use vars qw($tgz);

# sanity check the date - some browsers mangle decoding it
if (   $system
	&& $logdate
	&& $logdate =~ /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/
	&& $stage)
{
	my $db = DBI->connect($dsn, $dbuser, $dbpass);

	die $DBI::errstr unless $db;

	if ($logdate =~ /^latest$/i)
	{
		my $find_latest = qq{
            select max(snapshot)
            from build_status_log
            where sysname = ?
                and snapshot > now() - interval '30 days'
                and log_stage = ? || '.log'
                and branch = ?
        };
		my $logs =
		  $db->selectcol_arrayref($find_latest, undef, $system, $stage, $brnch);
		$logdate = shift(@$logs);
	}

	my $statement = q(

        select branch, log_text
        from build_status_log
        where sysname = ? and snapshot = ? and log_stage = ? || '.log'

        );

	my $sth = $db->prepare($statement);
	$sth->execute($system, $logdate, $stage);
	my $row = $sth->fetchrow_arrayref;
	my ($branch, $logtext);
	if ($row)
	{
		$branch  = $row->[0];
		$logtext = $row->[1];
	}
	$sth->finish;
	$db->disconnect;

	$branch ||= "unknown";

	print
	  "Content-Type: text/plain\nContent-disposition: inline; filename=$stage.log\n\n";

	if ($stage ne 'typedefs')
	{
		print "Snapshot: $logdate\n\n";
		$logtext ||= "no log text found";
	}


	$logtext =~
	  s/([\x00-\x08\x0B\x0C\x0E-\x1F\x80-\xff])/sprintf("\\x%.02x",ord($1))/ge
	  if $logtext;
	print $logtext if $logtext;

}

else
{
	print "Status: 460 bad parameters\n", "Content-Type: text/plain\n\n";
}

