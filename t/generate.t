# vim: ts=2 sw=2 expandtab

use warnings;
use strict;

use Test::More;

use POE::Test::Loops;

use File::Temp qw/ tempdir /;
use File::Find;

# could also use Test2 :-)
use Test::Deep;

my $tmpdir = tempdir( CLEANUP => 1 );

# simulate a simple usage as poe-gen-tests will do

my $ok = 1;
foreach my $dir ( 'POE', 'POE/Loop', 't' ) {
    $ok &= mkdir("$tmpdir/$dir");
    last unless $ok;
}

if ( !$ok ) {
    plan skip_all => 'Cannot create temporary directories. ' . $!;
}

my $dir_base     = $tmpdir . '/t';
my $loop_modules = ['Fake'];
my $flag_verbose = 0;

ok -d $dir_base, "dir_base is available" or die;

{
    if ( open( my $fh, '>', "$tmpdir/POE/Loop/Fake.pm" ) ) {
        print {$fh} "package POE::Loop:Fake;\n1\n";
        close($fh);
    }
    ok -e "$tmpdir/POE/Loop/Fake.pm", "create a fake POE::Loop::Fake module";
}

# add our current tmpdir to INC so we can find it
unshift @INC, $tmpdir;

note "POE::Test::Loops::generate";
POE::Test::Loops::generate(
    $dir_base,
    $loop_modules,
    $flag_verbose
);

my @tests;
File::Find::find(
    sub {
        my $f = $File::Find::name;

        return unless -f $f;

        $f =~ s{^$dir_base}{};
        push @tests, $f if length $f > 1;

        1;
    },
    $dir_base
);

my $got = [ sort @tests ];
cmp_deeply $got, [
    '/fake/00_info.t',
    '/fake/all_errors.t',
    '/fake/comp_tcp.t',
    '/fake/comp_tcp_concurrent.t',
    '/fake/connect_errors.t',
    '/fake/k_alarms.t',
    '/fake/k_aliases.t',
    '/fake/k_detach.t',
    '/fake/k_run_returns.t',
    '/fake/k_selects.t',
    '/fake/k_sig_child.t',
    '/fake/k_signals.t',
    '/fake/k_signals_rerun.t',
    '/fake/sbk_signal_init.t',
    '/fake/ses_nfa.t',
    '/fake/ses_session.t',
    '/fake/wheel_accept.t',
    '/fake/wheel_curses.t',
    '/fake/wheel_readline.t',
    '/fake/wheel_readwrite.t',
    '/fake/wheel_run.t',
    '/fake/wheel_run_size.t',
    '/fake/wheel_sf_ipv6.t',
    '/fake/wheel_sf_tcp.t',
    '/fake/wheel_sf_udp.t',
    '/fake/wheel_sf_unix.t',
    '/fake/wheel_tail.t',
    '/fake/z_kogman_sig_order.t',
    '/fake/z_leolo_wheel_run.t',
    '/fake/z_merijn_sigchld_system.t',
    '/fake/z_rt39872_sigchld.t',
    '/fake/z_rt39872_sigchld_stop.t',
    '/fake/z_rt53302_fh_watchers.t',
    '/fake/z_rt54319_bazerka_followtail.t',
    '/fake/z_steinert_signal_integrity.t'
    ],
    "all tests created as expected"
    or diag explain $got;

my $test_content;
{
    local $/;
    if ( open( my $fh, '<', "$dir_base/fake/00_info.t" ) ) {
        $test_content = <$fh>;
    }
}

my $expect = "#!$^X -w\n" . <<'EOS';

use strict;

use lib qw(lib/POE/Test/Loops);
use Test::More;
use POSIX qw(_exit);

sub skip_tests { return }

BEGIN {
  if (my $why = skip_tests('00_info')) {
    plan skip_all => $why
  }
}

# Run the tests themselves.
require '00_info.pm';

_exit 0 if $^O eq 'MSWin32';
CORE::exit 0;
EOS

is $test_content, $expect, "test content as expected" or diag $test_content;

done_testing;
