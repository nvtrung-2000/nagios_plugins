#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case);
use DBI;
use Parallel::ForkManager;
use Cache::FileCache;
use Time::HiRes qw(time);
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init({
    level   => $DEBUG,
    file    => ">>/var/log/nagios/asm_plugin.log",
    layout  => '%d %p %m %n',
});

use constant {
    DEFAULT_WARN_PERC => 85,
    DEFAULT_CRIT_PERC => 95,
    CACHE_EXPIRY => 300,  # 5 minutes
    MAX_PARALLEL_PROCESSES => 5,
};

use constant {
    SQL_CHECK_DGSTATE => q{SELECT STATE, name FROM v$asm_diskgroup},
    SQL_CHECK_USEDSPACE => q{
        SELECT NAME, 
            CEIL((total_mb - free_mb)/1024) used_gb, 
            CEIL((free_mb)/1024) free_gb, 
            CEIL(total_mb/1024) total_gb, 
            CEIL((total_mb - free_mb)/total_mb*100) as percentage_used 
        FROM v$asm_diskgroup
    },
    SQL_CHECK_DISKSTATUS => q{SELECT mode_status, path FROM v$asm_disk},
    SQL_CHECK_ALERTLOGERROR => q{
        SELECT count(*) 
        FROM X$DBGALERTEXT 
        WHERE ORIGINATING_TIMESTAMP > systimestamp-1 
        AND message_text LIKE '%ORA-%'
    },
};

my %nagios_exit_codes = ( 'UNKNOWN' => 3, 'OK' => 0, 'WARNING' => 1, 'CRITICAL' => 2 );
my %disk_groups_thresholds;
my ($asm_home, $action, $help);

GetOptions(
    'help' => \$help,
    'asm_home=s' => \$asm_home,
    'action=s' => \$action,
    'threshold=s' => \%disk_groups_thresholds
) or usage();

usage() if $help;

my $cache = Cache::FileCache->new({
    namespace => 'check_asm',
    default_expires_in => CACHE_EXPIRY,
});

my $sid = check_asm_running();

$ENV{ORACLE_SID} = $sid;
$ENV{ORACLE_HOME} = $asm_home;
delete $ENV{TWO_TASK};

my $dbh = connect_to_asm();

my %actions = (
    'status' => \&check_status,
    'dgstate' => \&check_dgstate,
    'usedspace' => \&check_usedspace,
    'diskstatus' => \&check_diskstatus,
    'alertlogerror' => \&check_alertlogerror,
);

if (exists $actions{$action}) {
    my ($status, $output_msg) = $actions{$action}->();
    print "[$status] $output_msg\n";
    exit $nagios_exit_codes{$status};
} else {
    print "[CRITICAL] Unknown action: $action\n";
    exit $nagios_exit_codes{'CRITICAL'};
}

sub connect_to_asm {
    my $dsn = "dbi:Oracle:$sid";
    my $dbh = DBI->connect($dsn, '/', '', { RaiseError => 1, AutoCommit => 0 });

    unless ($dbh) {
        Log::Log4perl->get_logger()->error("Failed to connect to ASM: $DBI::errstr");
        print "[CRITICAL] Failed to connect to ASM\n";
        exit $nagios_exit_codes{'CRITICAL'};
    }
    
    return $dbh;
}

sub check_asm_running {
    my $sid = qx[ps -eaf | grep asm_smon | grep -v grep];
    chomp $sid;
    $sid =~ s/.+asm_smon_(\W+)/$1/;
    
    if ($sid !~ m/ASM/) {
        print "[CRITICAL] ASM instance is down!\n";
        exit $nagios_exit_codes{'CRITICAL'};
    }
    return $sid;
}

sub check_status {
    return ('OK', "ASM instance is up");
}

sub check_dgstate {
    my $cache_key = 'dgstate';
    my $cached_result = check_cache_validity($cache_key);
    return @$cached_result if $cached_result;

    my $sth = $dbh->prepare(SQL_CHECK_DGSTATE);
    $sth->execute();
    
    my $output_msg = "Diskgroup state: ";
    my $status = 'OK';
    
    while (my ($dgstate, $dgname) = $sth->fetchrow_array()) {
        $dgname =~ s/\W+//;
        $output_msg .= "($dgname: $dgstate) ";
        $status = 'CRITICAL' if $dgstate ne 'MOUNTED';
    }
    
    $cache->set($cache_key, [$status, $output_msg, time]);
    return ($status, $output_msg);
}

sub check_usedspace {
    my $cache_key = 'usedspace';
    my $cached_result = check_cache_validity($cache_key);
    return @$cached_result if $cached_result;

    my $sth = $dbh->prepare(SQL_CHECK_USEDSPACE);
    $sth->execute();
    
    my $output_msg = "Diskgroup used space: ";
    my $status = 'OK';
    my $perfdata = "";
    my $long_text = "";
    
    while (my ($dgname, $used_gb, $free_gb, $total_gb, $percentage_used) = $sth->fetchrow_array()) {
        $dgname =~ s/\W+//;
        
        my ($warnPerc, $critPerc) = (DEFAULT_WARN_PERC, DEFAULT_CRIT_PERC);
        ($warnPerc, $critPerc) = split /:/, $disk_groups_thresholds{$dgname} if exists $disk_groups_thresholds{$dgname};
        
        if ($percentage_used >= $warnPerc && $percentage_used < $critPerc) {
            $status = 'WARNING' if $status eq 'OK';
            $output_msg .= "($dgname: $percentage_used% ($used_gb/$total_gb GB): WARNING) ";
            $long_text .= "Diskgroup $dgname is above the warning threshold ($warnPerc%). Consider adding more storage.\n";
        } elsif ($percentage_used >= $critPerc) {
            $status = 'CRITICAL';
            $output_msg .= "($dgname: $percentage_used% ($used_gb/$total_gb GB): CRITICAL) ";
            $long_text .= "Diskgroup $dgname is above the critical threshold ($critPerc%). Immediate action required.\n";
        } else {
            $output_msg .= "($dgname: $percentage_used% ($used_gb/$total_gb GB): OK) ";
        }
        $perfdata .= " $dgname=$percentage_used%;$warnPerc;$critPerc";
        
        delete($disk_groups_thresholds{$dgname});
    }
    $output_msg .= "| $perfdata";
    
    if ($status ne 'OK') {
        $output_msg .= "\n$long_text";
    }
    
    $cache->set($cache_key, [$status, $output_msg, time]);
    return ($status, $output_msg);
}

sub check_diskstatus {
    my $cache_key = 'diskstatus';
    my $cached_result = check_cache_validity($cache_key);
    return @$cached_result if $cached_result;

    my $sth = $dbh->prepare(SQL_CHECK_DISKSTATUS);
    $sth->execute();
    
    my $output_msg = "Disk status: ";
    my $status = 'OK';
    
    while (my ($diskstatus, $diskname) = $sth->fetchrow_array()) {
        $output_msg .= "($diskname - $diskstatus) ";
        $status = 'CRITICAL' if $diskstatus ne 'ONLINE';
    }
    
    $cache->set($cache_key, [$status, $output_msg, time]);
    return ($status, $output_msg);
}

sub check_alertlogerror {
    my $cache_key = 'alertlogerror';
    my $cached_result = check_cache_validity($cache_key);
    return @$cached_result if $cached_result;

    my $sth = $dbh->prepare(SQL_CHECK_ALERTLOGERROR);
    $sth->execute();
    
    my ($numerrors) = $sth->fetchrow_array();
    my $status = $numerrors == 0 ? 'OK' : 'WARNING';
    my $output_msg = "ASM AlertLog Errors: $numerrors";
    
    $cache->set($cache_key, [$status, $output_msg, time]);
    return ($status, $output_msg);
}

sub check_cache_validity {
    my ($cache_key) = @_;
    my $cached_result = $cache->get($cache_key);

    if ($cached_result) {
        my ($status, $output, $timestamp) = @$cached_result;

        if (time - $timestamp < CACHE_EXPIRY) {
            return ($status, $output);
        }
    }
    
    return undef;
}

sub usage {
    print qq[
Usage: $0 --help --asm_home <ORACLE_HOME for ASM> --action <ACTION> --threshold <GROUP_DISK=integer> [[--threshold <GROUP_DISK=integer>] ...]

Examples:
    $0 --asm_home /u01/app/oracle/product/11.2.0/asm --action usedspace --threshold DATA=80:90
    $0 --asm_home /u01/app/oracle/product/11.2.0/asm --action status

Options:
    --help:         prints this info
    --asm_home:     ORACLE_HOME for asm instance
    --action:       status|dgstate|diskstatus|usedspace|alertlogerror
    --threshold:    GROUP_DISK_NAME=WarnPerc:CritPerc - percentage threshold for used space (range [0..100]) - use for <usedspace> action
    ];
    exit $nagios_exit_codes{'WARNING'};
}
