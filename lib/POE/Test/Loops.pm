# vim: ts=2 sw=2 expandtab

package POE::Test::Loops;

use warnings;
use strict;

use File::Spec;
use File::Path;
use File::Find;

use constant TEST_BLOCK_FOR_WHICH => 0x01;
use constant TEST_BLOCK_FOR_WRONG => 0x02;
use constant TEST_BLOCK_FOR_RIGHT => 0x04;
use constant TEST_BLOCK_BEGIN     => 0x08;

### Find the test libraries.

use lib qw(./lib ../lib);
use POE::Test::DondeEstan;
my $source_base = POE::Test::DondeEstan->marco();

### Generate loop tests.

sub generate {
  my ($dir_base, $loops, $flag_verbose) = @_;

  foreach my $loop (@$loops) {
    my $loop_dir = lc($loop);
    $loop_dir =~ s/::/_/g;

    my $fqmn = _find_event_loop_file($loop);
    unless ($fqmn) {
      $flag_verbose and print "Couldn't find a loop for $loop ...\n";
      next;
    }

    $flag_verbose and print "Found $fqmn\n";

    my $loop_cfg = _get_loop_cfg($fqmn);
    unless (defined $loop_cfg and length $loop_cfg) {
      $loop_cfg = (
				"sub skip_tests { return }"
			);
    }

    my $source = <<"EOS";
#!/usr/bin/perl -w

use strict;

use lib qw(--base_lib--);
use Test::More;
use POSIX qw(_exit);

--loop_cfg--

BEGIN {
  if (my \$why = skip_tests('--test_name--')) {
    plan skip_all => \$why
  }
}

# Run the tests themselves.
require '--base_file--';

_exit 0 if \$^O eq 'MSWin32';
CORE::exit 0;
EOS

		# Full directory where source files are found.

    my $dir_src = File::Spec->catfile($source_base, "Loops");
    my $dir_dst = File::Spec->catfile($dir_base, $loop_dir);

		# Gather the list of source files.
		# Each will be used to generate a real test file.

    opendir BASE, $dir_src or die $!;
    my @base_files = grep /\.pm$/, readdir(BASE);
    closedir BASE;

		# Initialize the destination directory.  Clear or create as needed.

    $dir_dst =~ tr[/][/]s;
    $dir_dst =~ s{/+$}{};

    rmtree($dir_dst);
    mkpath($dir_dst, 0, 0755);

		# For each source file, generate a corresponding one in the
		# configured destination directory.  Expand various bits to
		# customize the test.

    foreach my $base_file (@base_files) {
      my $test_name = $base_file;
      $test_name =~ s/\.pm$//;

      my $full_file = File::Spec->catfile($dir_dst, $base_file);
      $full_file =~ s/\.pm$/.t/;

			# These hardcoded expansions are for the base file to be required,
			# and the base library directory where it'll be found.

      my $expanded_src = $source;
      $expanded_src =~ s/--base_file--/$base_file/g;
      $expanded_src =~ s/--base_lib--/$dir_src/g;
      $expanded_src =~ s/--loop_cfg--/$loop_cfg/g;
      $expanded_src =~ s/--test_name--/$test_name/g;

			# Write with lots of error checking.

      open EXPANDED, ">$full_file" or die $!;
      print EXPANDED $expanded_src;
      close EXPANDED or die $!;
    }
  }
}

sub _find_event_loop_file {
  my $loop_name = shift;

  my $loop_module;
  if ($loop_name =~ /^POE::/) {
    $loop_module = File::Spec->catfile(split(/::/, $loop_name)) . ".pm";
  }
  else {
    $loop_name =~ s/::/_/g;
    $loop_module = File::Spec->catfile("POE", "Loop", $loop_name) .  ".pm";
  }

  foreach my $inc (@INC) {
    my $fqmn = File::Spec->catfile($inc, $loop_module);
    next unless -f $fqmn;
    return $fqmn;
  }

  return;
}

sub _get_loop_cfg {
  my $fqmn = shift;

  my ($in_test_block, @test_source);

  open SOURCE, "<$fqmn" or die $!;
  while (<SOURCE>) {
    # Not in a test block.
    unless ($in_test_block) {

      # Proper =for syntax.
      if (/^=for\s+poe_tests\s+(\S.*?)$/) {
        push @test_source, $1;
        $in_test_block = TEST_BLOCK_FOR_RIGHT;
        next;
      }

      # Not sure which =for syntax is in use.
      if (/^=for\s+poe_tests\s*$/) {
        $in_test_block = TEST_BLOCK_FOR_WHICH;
        next;
      }

      if (/^=begin\s+(poe_tests)\s*$/) {
        $in_test_block = TEST_BLOCK_BEGIN;
        next;
      }

      # Some random line.  Do nothing.
      next;
    }

    # Which test block format are we in?
    if ($in_test_block & TEST_BLOCK_FOR_WHICH) {
      # If the following line is blank, then we're probably in the
      # wrong, multi-line kind originally documented and now
      # deprecated.
      if (/^\s*$/) {
        $in_test_block = TEST_BLOCK_FOR_WRONG;
        next;
      }

      # The following line is not blank, so it appears we're in a
      # properly formatted =for paragraph.
      $in_test_block = TEST_BLOCK_FOR_RIGHT;
      push @test_source, $_;
      next;
    }

    # The =begin syntax ends with an =end.
    if ($in_test_block & TEST_BLOCK_BEGIN) {
      if (/^=end\s*poe_tests\s*$/) {
        $in_test_block = 0;
        next;
      }

      # Be helpful?
      die "=cut not the proper way to end =begin poe_tests" if /^=cut\s*$/;

      push @test_source, $_;
      next;
    }

    # The proper =for syntax ends on a blank line.
    if ($in_test_block & TEST_BLOCK_FOR_RIGHT) {
      if (/^$/) {
        $in_test_block = 0;
        next;
      }

      # Be helpful?
      die "=cut not the proper way to end =for poe_tests" if /^=cut\s*$/;

      push @test_source, $_;
      next;
    }

    # The wrong =for syntax ends on =cut.
    if ($in_test_block & TEST_BLOCK_FOR_WRONG) {
      if (/^=cut\s*$/) {
        $in_test_block = 0;
        next;
      }

      # Be helpful?
      die "=end not the proper way to end =for poe_tests" if /^=end/;

      push @test_source, $_;
      next;
    }

    die "parser in unknown state: $in_test_block";
  }

  shift @test_source while @test_source and $test_source[0] =~ /^\s*$/;
  pop @test_source while @test_source and $test_source[-1] =~ /^\s*$/;

  return join "", @test_source;
}

1;

__END__

=head1 NAME

POE::Test::Loops - Reusable tests for POE::Loop authors

=head1 SYNOPSIS

	#!/usr/bin/perl -w

	use strict;
	use Getopt::Long;
	use POE::Test::Loops;

	my ($dir_base, $flag_help, @loop_modules, $flag_verbose);
	my $result = GetOptions(
		'dirbase=s' => \$dir_base,
		'loop=s' => \@loop_modules,
		'verbose' => \$flag_verbose,
		'help' => \$flag_help,
	);

	if (
		!$result or !$dir_base or $flag_help or !@loop_modules
	) {
		die(
			"$0 usage:\n",
			"  --dirbase DIR   (required) base directory for tests\n",
			"  --loop MODULE   (required) loop modules to test\n",
			"  --verbose   show some extra output\n",
			"  --help   you're reading it\n",
		);
	}

	POE::Test::Loops::generate($dir_base, \@loop_modules, $flag_verbose);
	exit 0;

=head1 DESCRIPTION

POE::Test::Loops contains one function, generate(), which will
generate all the loop tests for one or more POE::Loop subclasses.

The L</SYNOPSIS> example is a version of L<poe-gen-tests>, which is a
stand-alone utility to generate the actual tests.  L<poe-gen-tests>
also documents the POE::Test::Loops system in more detail.

=head1 FUNCTIONS

=head2 generate( $DIRBASE, \@LOOPS, $VERBOSE )

Generates the loop tests.  DIRBASE is the (relative) directory in
which a subdirectory for each of the LOOPS is created.  If VERBOSE is
set to a TRUE value some progress reporting is printed.

	POE::Test::Loops::generate(
		"./t",
		[ "POE::Loop::Yours" ],
		1,
	);

=head1 SEE ALSO

L<POE::Loop> and L<poe-gen-tests>.

=head1 AUTHOR & COPYRIGHT

See L<poe-gen-tests>.

=cut
