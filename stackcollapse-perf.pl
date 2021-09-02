#!/usr/bin/perl -w
#
# stackcolllapse-perf.pl	collapse perf samples into single lines.
#
# Parses a list of multiline stacks generated by "perf script", and
# outputs a semicolon separated stack followed by a space and a count.
# If memory addresses (+0xd) are present, they are stripped, and resulting
# identical stacks are colased with their counts summed.
#
# USAGE: ./stackcollapse-perf.pl infile > outfile
#
# Example input:
#
#  swapper     0 [000] 158665.570607: cpu-clock: 
#         ffffffff8103ce3b native_safe_halt ([kernel.kallsyms])
#         ffffffff8101c6a3 default_idle ([kernel.kallsyms])
#         ffffffff81013236 cpu_idle ([kernel.kallsyms])
#         ffffffff815bf03e rest_init ([kernel.kallsyms])
#         ffffffff81aebbfe start_kernel ([kernel.kallsyms].init.text)
#  [...]
#
# Example output:
#
#  swapper;start_kernel;rest_init;cpu_idle;default_idle;native_safe_halt 1
#
# Input may be created and processed using:
#
#  perf record -a -g -F 997 sleep 60
#  perf script | ./stackcollapse-perf.pl > out.stacks-folded
#
# Copyright 2012 Joyent, Inc.  All rights reserved.
# Copyright 2012 Brendan Gregg.  All rights reserved.
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at docs/cddl1.txt or
# http://opensource.org/licenses/CDDL-1.0.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at docs/cddl1.txt.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
# 02-Mar-2012	Brendan Gregg	Created this.
# 02-Jul-2014	   "	  "	Added process name to stacks.

use strict;

my %collapsed;

sub remember_stack {
	my ($stack, $count) = @_;
	$collapsed{$stack} += $count;
}

my @stack;
my $pname;
my $include_pname = 1;	# include process names in stacks
my $tidy_java = 1;	# condense Java signatures
my $tidy_generic = 1;	# clean up function names a little

foreach (<>) {
	next if m/^#/;
	chomp;

	if (m/^$/) {
		if ($include_pname) {
			if (defined $pname) {
				unshift @stack, $pname;
			} else {
				unshift @stack, "";
			}
		}
		remember_stack(join(";", @stack), 1) if @stack;
		undef @stack;
		undef $pname;
		next;
	}

	if (/^(\S+)\s/) {
		$pname = $1;
	} elsif (/^\s*\w+\s*(.+) (\S+)/) {
		my ($func, $mod) = ($1, $2);
		next if $func =~ /^\(/;		# skip process names
		if ($tidy_generic) {
			$func =~ s/;/:/g;
			$func =~ tr/<>//d;
			$func =~ s/\(.*//;
			# now tidy this horrible thing:
			# 13a80b608e0a RegExp:[&<>\"\'] (/tmp/perf-7539.map)
			$func =~ tr/"\'//d;
			# fall through to $tidy_java
		}
		if ($tidy_java and $pname eq "java") {
			# along with $tidy_generic, converts the following:
			#	Lorg/mozilla/javascript/ContextFactory;.call(Lorg/mozilla/javascript/ContextAction;)Ljava/lang/Object;
			#	Lorg/mozilla/javascript/ContextFactory;.call(Lorg/mozilla/javascript/C
			#	Lorg/mozilla/javascript/MemberBox;.<init>(Ljava/lang/reflect/Method;)V
			# into:
			#	org/mozilla/javascript/ContextFactory:.call
			#	org/mozilla/javascript/ContextFactory:.call
			#	org/mozilla/javascript/MemberBox:.init
			$func =~ s/^L// if $func =~ m:/:;
		}
		unshift @stack, $func;
	} else {
		warn "Unrecognized line: $_";
	}
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
